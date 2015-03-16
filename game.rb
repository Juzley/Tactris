require 'rubygems'
require 'chingu'
require 'logger'

include Gosu
include Chingu

#---------------------
# Utility Classes
#---------------------

# Drawing order
module ZOrder
  Map, Unit, Effect = *0..2
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
  def draw_size(x, y, z, width, height, color=0xffffffff)
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
    self.x == other.x && self.y == other.y
  end
end


#--------------------
# Game Classes
#--------------------

# Main Game Window
class Game < Chingu::Window
  def initialize
    super(300, 600)
    self.input = {:esc => :exit}

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
      :left_mouse_button => lambda {
          @mouse_down_pos.set($window.mouse_x, $window.mouse_y) },
      :released_left_mouse_button => :left_mouse_up }
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
    # TODO: Have an advancing enemy front line that units can't be put in?
    # TODO: Need to stop adding/moving units while the board is scrolling?
    #       Or allow it and adjust coords accordingly, double scroll etc.
    
    # Check if this is a drag from one cell to another or a click
    # on a single cell.
    down_tile = @board.mouse_pos_to_tile_coords(@mouse_down_pos)
    up_tile = @board.mouse_pos_to_tile_coords(
                      Point.new($window.mouse_x, $window.mouse_y))
    logger.info "Left Mouse Released: Down #{down_tile}, Up #{up_tile}"

    if up_tile == down_tile
      if @board.tile_empty?(down_tile)
        # The tile needs to be empty to place new units on
        logger.info "Add Unit"
        @board.add_unit(down_tile)
      end
    else
      # TODO: Check for move patterns, blocking tiles etc. 
      if @board.tile_contains_friendly_unit?(down_tile) &&
        @board.tile_empty?(up_tile)
        logger.info "Move Unit"
        @board.move_unit(down_tile, up_tile)
      end
    end
  end
end

class Board
  COLUMNS = 10
  VISIBLE_ROWS = 20
  TOTAL_ROWS = VISIBLE_ROWS + 1
  NUM_TILES = TOTAL_ROWS * COLUMNS
  PROGRESS_TIME = 5000 # Time between board progression, in ms
  TRANSITION_TIME = 500 # Time taken to move the board, in ms

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
    @tiles = Array.new(NUM_TILES) do |i|
      Tile.new(self, Tile::TYPES.sample)
    end
    @tiles[NUM_TILES - 1].unit = Tank.new(@tiles[NUM_TILES - 1], :enemy)

    @tile_width = ($window.width / COLUMNS).round
    @tile_height = ($window.height / VISIBLE_ROWS).round

    @enemy_rows = 1

    @status = :default
    @progress_time = 0
    @transition_time = 0
    @draw_offset = 0
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
          tile.type = Tile::TYPES.sample
          tile.unit = nil
        end

        @tiles.each { |tile| tile.unit.run if tile.unit != nil }
      else
        @draw_offset = @transition_time.fdiv(TRANSITION_TIME) * @tile_height
      end
    end

    @progress_time += $window.milliseconds_since_last_tick
    if @progress_time > PROGRESS_TIME
      progress
    end

    @tiles.each { |tile| tile.unit.update if tile.unit != nil }
  end

  def draw
    0.upto(TOTAL_ROWS - 1) do |row|
      0.upto(COLUMNS - 1) do |col|
        @tiles[row * COLUMNS + col].draw(
          col * @tile_width,
          $window.height - (row + 1) * @tile_height + @draw_offset,
          @tile_width, @tile_height,
          # TODO: Draw this over the top rather than coloring the tiles?
          row > 10 ? 0xffff5555 : 0xffffffff)
      end
    end
  end
  
  def walk_tiles(tile, pattern, &walker)
    start_index = @tiles.find_index(tile)
    throw "Invalid tile" if start_index == nil

    pattern.each do |coord|
      # Coord specifies the [column, row] offset from the start tile
      # of the tile to walk
      tile_index = start_index + coord[0] + coord[1] * COLUMNS
  
      # Check that the tile is in valid range
      if tile_index >=0 && tile_index < COLUMNS * VISIBLE_ROWS
        yield @tiles[tile_index]
      end
    end
  end

  def progress
    @progress_time = 0
    @transition_time = 0
    @status = :scroll
  end

  def mouse_pos_in_board?(mouse_pos)
    # Always true while board takes up whole screen
    return true
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
    tile.unit = Tank.new(tile, :friendly)
    progress
  end

  def move_unit(from_coord, to_coord)
    from_tile = get_tile(from_coord)
    to_tile = get_tile(to_coord)

    to_tile.unit = from_tile.unit
    from_tile.unit = nil

    to_tile.unit.tile = to_tile

    progress
  end

  def tile_contains_friendly_unit?(tile_coord)
    unit = get_tile(tile_coord).unit
    unit != nil && unit.friendly?
  end

  def tile_empty?(tile_coord)
    get_tile(tile_coord).empty?
  end
end

class Tile
  TYPES = [:tile_ground, :tile_mountain]

  attr_accessor :type
  attr_accessor :unit

  def self.load_media
    @@images ||= { :tile_ground => Image["Earth.png"],
                   :tile_mountain => Image["stone_wall.bmp"] }
  end

  def initialize(board, type, unit=nil)
    @board = board
    @type = type
    @unit = unit
  end

  def draw(x, y, width, height, color=0xffffffff)
    @@images[@type].draw_size(x, y, ZOrder::Map, width, height, color)
    @unit.draw(x, y, width, height) if @unit != nil
  end

  def empty?
    @unit == nil
  end

  def walk_surrounding(walk_pattern, &walker)
    @board.walk_tiles(self, walk_pattern, &walker)
  end
end


#---------------
# Units
#---------------

class Unit
  attr_accessor :tile

  def initialize(tile, type)
    @type = type
    @tile = tile
    @state = :idle
  end

  def draw(x, y, width, height)
    @image.draw_size(x, y, ZOrder::Unit, width, height)
  end

  def friendly?
    @type == :friendly
  end

  def enemy?
    @type == :enemy
  end

  def dead?
    @state == :dead
  end

  def update
  end

  def run
  end

  def damage
  end
end

# TODO: Some of this should be in the base class
class Tank < Unit
  Fire_pattern = [[0,1], [0,2], [0,3]]

  def initialize(tile, type)
    super(tile, type)

    @animation = Chingu::Animation.new(:file => "droid_11x15.bmp")
    @animation.frame_names = { :dead => 0..5, :fire => 6..7, :idle => 8..9  }
    @animation[:dead].loop = false
    @animation[:fire].loop = false
    @image = @animation[:idle].first

    @state = :idle
  end

  def update
    @image = @animation[@state].next

    # If this unit is dead, unlink it from the board once the
    # death animation is finished
    if @state == :dead && @animation[@state].last_frame?
      @tile.unit = nil
    end

    if @state == :fire && @animation[@state].last_frame?
      @state = :idle
    end
  end

  def run
    # Find if there's something we can shoot at
    @tile.walk_surrounding(Fire_pattern) do |tile|
      # Can't shoot through mountains
      break if tile.type == :tile_mountain

      if tile.unit != nil && tile.unit.enemy? && !tile.unit.dead?
        @state = :fire
        tile.unit.damage
        break
      end
    end
  end

  def damage
    @state = :dead
  end
end


#-------------
# Main
#-------------

Game.new.show

