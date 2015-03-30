require 'rubygems'
require 'chingu'
require 'logger'
require_relative 'unit.rb'

include Gosu
include Chingu

# TODO: How it's going to work:
# - Playing field:
#     Playing field advances downwards. Enemies spawn at the top.
#     Player units drive 'forwards' (i.e. remain in the same place on the
#     screen despite the field moving), unless they hit a mountain or
#     something.
# - Battle line:
#     Units can only be placed below the battle line.
#     Battle line advances when the player messes up (exactly what TBD - maybe
#     when the an enemy unit reaches the bottom? When the player loses a unit?)
#     Can be pushed back by the player doing well (killing enemy units?).
#     Game is over when the battle line reaches the bottom.
# - Action points:
#     Player has a set number of action points. Placing units, moving units
#     etc. use action points.
#     Gain action points back over time, plus for killing enemy units etc.
#
# - Unit types:
#   Infantry
#   Tank
#   Artillery
#   Bomber (enemy only)
#   Anti Air
#
# - Misc ideas:
#     Want to avoid just being able to place a single unit per enemy, so
#     want to force:
#       1. Having to use a single unit to cover multiple enemies (e.g. a
#       ranged dude that hits multiple targets.
#       2. Having to use multiple enemies of different types to kill the one
#       enemy.
#
#     Different 'colours' of enemy, killed by different types of unit?
#     'Super' units, that the player wants to protect? Could have a
#     'commander' style unit that the player has to protect?

#---------------------
# Utility Classes
#---------------------

# Drawing order
module ZOrder
  MAP, UNIT, EFFECT = *0..2
end

# Logging mixin
module Logging
  # This is the magical bit that gets mixed into your classes
  def logger
    Logging.logger
  end

  # Global, memoized, lazy initialized instance of a logger
  def self.logger
    @logger ||= Logger.new(STDOUT)
  end
end

# Extend Gosu::Image to allow drawing images at a certain size
class Gosu::Image
  def draw_size(x, y, z, width, height, color = 0xffffffff)
    draw(x, y, z, width.fdiv(self.width), height.fdiv(self.height), color)
  end
end

# A 2D point
class Point
  attr_accessor :x, :y

  def initialize(x = 0, y = 0)
    set(x, y)
  end

  def set(x = 0, y = 0)
    @x, @y = x, y
  end

  def to_s
    "Point(#{x}, #{y})"
  end

  def ==(other)
    @x == other.x && @y == other.y
  end
end

class WeightedRandomSelector
  def initialize(weights)
    @array = []
    weights.each do |item, count|
      @array += [item] * count
    end
  end

  def sample
    @array.sample
  end
end

#--------------------
# Game Classes
#--------------------

# Main Game Window
class Game < Chingu::Window
  def initialize
    super(600, 600)
    self.input = { esc: :exit }

    # TODO: do we need to preload like this?
    Tile.load_media

    push_game_state(Play)
  end

  def needs_cursor?
    true
  end
end

# GameState for the actual game
class Play < Chingu::GameState
  include Logging

  def initialize
    super

    @mouse_down_pos = Point.new

    self.input = {
      left_mouse_button: lambda {
          @mouse_down_pos.set($window.mouse_x, $window.mouse_y) },
      released_left_mouse_button: :left_mouse_up }
  end

  def setup
    @board = Board.new
  end

  def update
    @board.update
  end

  def draw
    @board.draw
  end

  def left_mouse_up
    # TODO: Check the mouse pos is in the board, or elsewhere
    # TODO: Need to stop adding/moving units while the board is scrolling?
    #       Or allow it and adjust coords accordingly, double scroll etc.

    # Check if this is a drag from one cell to another or a click
    # on a single cell.
    down_tile = @board.mouse_pos_to_tile_coords(@mouse_down_pos)
    up_tile = @board.mouse_pos_to_tile_coords(
                      Point.new($window.mouse_x, $window.mouse_y))
    logger.info "Left Mouse Released: Down #{down_tile}, Up #{up_tile}"

    if up_tile == down_tile
      if @board.tile_empty?(down_tile) &&
          !@board.tile_enemy_territory?(down_tile)
        # The tile needs to be empty to place new units on
        logger.info('Add Unit')
        @board.add_unit(down_tile)
      end
    else
      # TODO: Check for move patterns, blocking tiles etc.
      if @board.tile_contains_friendly_unit?(down_tile) &&
         @board.tile_ground_empty?(up_tile)
        logger.info('Move Unit')
        @board.move_unit(down_tile, up_tile)
      end
    end
  end
end

class Board
  COLUMNS = 20
  VISIBLE_ROWS = 20
  TOTAL_ROWS = VISIBLE_ROWS + 1
  NUM_TILES = TOTAL_ROWS * COLUMNS
  PROGRESS_TIME = 5000 # Time between board progression, in ms
  TRANSITION_TIME = 0 # Time taken to move the board, in ms
  FRONTLINE_START = 15

  def initialize
    # Tiles array arranged in rows, from the bottom of the
    # screen to the top. Tiles within rows are arranged from
    # left to right.
    # An extra row is created off the top of the screen for
    # when the board scrolls down.
    #
    #   |C1 C2 C3
    # --|--------
    # R3|
    # R2|
    # R1|
    #
    # [ (C1, R1), (C2, R1), (C3, R1), (C1, R2) ... etc ... ]
    # TODO: Replace with proper tile generation + enemy placement
    @tilegen = WeightedRandomSelector.new({ tile_ground: 95,
                                            tile_mountain: 5 })
    @tiles = Array.new(NUM_TILES) do
      Tile.new(self, @tilegen.sample)
    end
    @tiles[NUM_TILES - 1].ground_unit =
      Tank.new(@tiles[NUM_TILES - 1], :enemy)

    @tile_width = ($window.width / COLUMNS).round
    @tile_height = ($window.height / VISIBLE_ROWS).round

    @frontline = FRONTLINE_START

    @status = :default
    @progress_time = 0
    @transition_time = 0
    @draw_offset = 0
  end

  def tile_index_to_coords(index)
    Point.new(index % COLUMNS, (index / COLUMNS).floor)
  end

  def tile_coords_to_index(coords)
    coords.x  + COLUMNS * coords.y
  end

  def update
    case @status
    when :scroll
      @transition_time += $window.milliseconds_since_last_tick

      if @transition_time > TRANSITION_TIME
        # The transition has finished, swap the bottom row of the board
        # to the top, ready for re-use next transition
        @status = :default
        @transition_time = 0
        @draw_offset = 0
        @tiles.rotate!(COLUMNS)

        # TODO: recycle bottom tiles, unlink old units
        @tiles[-COLUMNS, COLUMNS].each do |tile|
          tile.type = @tilegen.sample
          tile.ground_unit = nil
          tile.air_unit = nil
        end

        # Friendly units run first.
        @tiles.each do |tile|
          tile.each_unit { |unit| unit.run if unit.friendly? }
        end
        @tiles.each do |tile|
          tile.each_unit { |unit| unit.run if unit.enemy? }
        end
      else
        @draw_offset = @transition_time.fdiv(TRANSITION_TIME) * @tile_height
      end
    end

    @progress_time += $window.milliseconds_since_last_tick
    if @progress_time > PROGRESS_TIME
      progress
    end

    @tiles.each { |tile| tile.each_unit { |unit| unit.update } }
  end

  def draw
    0.upto(TOTAL_ROWS - 1) do |row|
      0.upto(COLUMNS - 1) do |col|
        @tiles[row * COLUMNS + col].draw(
          col * @tile_width,
          $window.height - (row + 1) * @tile_height + @draw_offset,
          @tile_width, @tile_height,
          # TODO: Draw this over the top rather than coloring the tiles?
          row > @frontline ? 0xffff5555 : 0xffffffff)
      end
    end
  end
  
  def walk_tiles(tile, pattern, orientation = :up, &walker)
    start_index = @tiles.find_index(tile)
    throw 'Invalid tile' if start_index == nil

    pattern.each do |coord|
      # Coord specifies the [column, row] offset from the start tile
      # of the tile to walk
      # Need first to transform this by the orientation - patterns are
      # specified assuming an 'up' orientation
      tc = coord
      case orientation
      when :down
        tc[0] *= -1
      when :right
        tc = [tc[1], tc[0]]
      when :left
        tc = [tc[1] * -1, tc[0]]
      end
      tile_index = start_index + tc[0] + COLUMNS * tc[1]

      # Check that the tile is in valid range
      if tile_index >= 0 && tile_index < COLUMNS * VISIBLE_ROWS
        yield @tiles[tile_index]
      end
    end
  end

  def progress
    @progress_time = 0
    @transition_time = 0
    @status = :scroll

    # Move ground units up the board (they stay at the same position on the
    # screen)
    (@tiles.length - 1).downto(0) do |i|
      tile = @tiles[i]
      tile_coords = tile_index_to_coords(i)
      next_coords = Point.new(tile_coords.x, tile_coords.y + 1)
      next_tile = get_tile(next_coords)

      if !tile.ground_unit.nil? && tile.ground_unit.friendly? &&
        next_tile.ground_empty?
        puts "Moving unit from #{tile_coords} to #{next_coords}"

        next_tile.ground_unit = tile.ground_unit
        next_tile.ground_unit.tile = next_tile
        tile.ground_unit = nil
      end
    end
  end

  def mouse_pos_in_board?(mouse_pos)
    # Always true while board takes up whole screen
    true
  end

  def mouse_pos_to_tile_coords(mouse_pos)
    Point.new((mouse_pos.x.fdiv(@tile_width)).floor,
              VISIBLE_ROWS - 1 -  (mouse_pos.y.fdiv(@tile_height)).floor)
  end

  def get_tile(tile_coord)
    @tiles[tile_coord.y * COLUMNS + tile_coord.x]
  end

  def add_unit(tile_coord)
    tile = get_tile(tile_coord)
    tile.ground_unit = Tank.new(tile, :friendly)
    progress
  end

  def move_unit(from_coord, to_coord)
    from_tile = get_tile(from_coord)
    to_tile = get_tile(to_coord)

    to_tile.gound_unit = from_tile.ground_unit
    from_tile.ground_unit = nil

    to_tile.ground_unit.tile = to_tile

    progress
  end

  def tile_contains_friendly_unit?(tile_coord)
    unit = get_tile(tile_coord).ground_unit
    !unit.nil? && unit.friendly?
  end

  def tile_ground_empty?(tile_coord)
    get_tile(tile_coord).ground_empty?
  end

  def tile_air_empty?(tile_coord)
    get_tile(tile_coord).air_empty?
  end

  def tile_empty?(tile_coord)
    get_tile(tile_coord).empty?
  end

  def tile_enemy_territory?(tile_coord)
    tile_coord.y > @frontline
  end
end

class Tile
  # TODO: Water, oil?
  TYPES = [:tile_ground, :tile_mountain]

  attr_accessor :type
  attr_accessor :ground_unit
  attr_accessor :air_unit

  def self.load_media
    @@images ||= { tile_ground: Image["Earth.png"],
                   tile_mountain: Image["stone_wall.bmp"] }
  end

  def initialize(board, type, ground_unit=nil, air_unit=nil)
    @board = board
    @type = type
    @ground_unit = ground_unit
    @air_unit = air_unit
  end

  def draw(x, y, width, height, color = 0xffffffff)
    @@images[@type].draw_size(x, y, ZOrder::MAP, width, height, color)

    self.each_unit { |unit| unit.draw(x, y, width, height) }
  end

  def ground_empty?
    @type != :tile_mountain && @ground_unit.nil?
  end

  def air_empty?
    @air_unit.nil?
  end

  def empty?
    ground_empty? && air_empty?
  end

  def each_unit
    yield @ground_unit if !@ground_unit.nil?
    yield @air_unit if !@air_unit.nil?
  end

  def walk_surrounding(walk_pattern, orientation = :up, &walker)
    @board.walk_tiles(self, walk_pattern, orientation, &walker)
  end
end


#-------------
# Main
#-------------

Game.new.show
