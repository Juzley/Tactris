require 'rubygems'
require 'chingu'
require_relative 'unit'
require_relative 'util'
require_relative 'edit'

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
#
#     Pre-define levels rather than having randomly generated? Better control
#     over difficulty that way.


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

  AP_MAX = 100 # The maximum number of action points.
  AP_REGEN_RATE = 10 # Rate that AP regenerates, per second.
  AP_REGEN_PERIOD = 1000 # Pause between regenerating AP.
 
  def initialize
    super

    @mouse_down_pos = Point.new

    @ap = AP_MAX 
    @ap_regen_time = 0
    @ap_text = Text.new(@ap.to_s, :x => 0, :y => 0, :zorder => ZOrder::HUD)

    @next_unit = Infantry

    self.input = {
      a: lambda {@next_unit = Artillery; puts @next_unit},
      i: lambda {@next_unit = Infantry; puts @next_unit},
      t: lambda {@next_unit = Tank; puts @next_unit},
      e: lambda {push_game_state(Edit.new(@board))},
      left_mouse_button: lambda {
          @mouse_down_pos.set($window.mouse_x, $window.mouse_y) },
      released_left_mouse_button: :left_mouse_up }
  end

  def setup
    @board = Board.new
  end

  def update
    # Regenerate AP
    @ap_regen_time += $window.milliseconds_since_last_tick
    if @ap_regen_time > AP_REGEN_PERIOD
      @ap += AP_REGEN_RATE * (1000 / AP_REGEN_PERIOD)
      @ap = [@ap, AP_MAX].min

      @ap_regen_time -= AP_REGEN_PERIOD
    end

    # Update the board
    @board.update
  end

  def draw
    @board.draw
    @ap_text.draw(@ap.to_s)
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
          !@board.tile_enemy_territory?(down_tile) &&
          @ap > @next_unit.move_ap
        # The tile needs to be empty to place new units on
        # TODO: consider air/ground units?
        logger.info('Add Unit')
        @board.add_unit(@next_unit.new(:friendly), down_tile)
        @ap -= @next_unit.move_ap
      end
    else
      # TODO: Check for move patterns, blocking tiles etc.
      move_unit = @board.get_friendly_unit(down_tile)
      if @ap > move_unit.move_ap &&
         @board.move_legal?(move_unit, up_tile)
        # The move is legal.
        logger.info('Move Unit')
        @board.move_unit(move_unit, up_tile)
        @ap - move_unit.move_ap
      end
    end
  end
end

class Board
  BOARD_HEIGHT = 560
  COLUMNS = 20
  VISIBLE_ROWS = 20
  TOTAL_ROWS = VISIBLE_ROWS + 1
  NUM_TILES = TOTAL_ROWS * COLUMNS
  PROGRESS_TIME = 5000 # Time between board progress, in ms
  TRANSITION_TIME = 0 # Time taken to move the board, in ms
  NEW_LEVEL_ROWS = 1000 # Number of rows when creating a new level
  FRONTLINE_START = 15

  attr_accessor :base_row
  attr_reader :rows

  def initialize(level = nil)
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
    @enemygen = WeightedRandomSelector.new({ Infantry: 3,
                                             Tank: 2,
                                             Artillery: 2,
                                             Bomber: 1 })

    # TODO: Load level
    if level.nil?
      @rows = NEW_LEVEL_ROWS

      @tiles = Array.new(@rows) do
        Tile.new(self, @tilegen.sample)
      end
    end
    @base_row = 0

    @tile_width = ($window.width / COLUMNS).round
    @tile_height = (BOARD_HEIGHT / VISIBLE_ROWS).round

    @frontline = FRONTLINE_START

    @status = :default
    @progress_time = 0
    @transition_time = 0
    @draw_offset = 0
  end

  def tile_index_to_coords(index)
    # Convert an index in the tile array to coordinate on screen.
    Point.new(index % COLUMNS, (index / COLUMNS).floor - @base_row)
  end

  def tile_coords_to_index(coords)
    # Convert a coordinate on screen to an index in the tile array.
    coords.x + COLUMNS * coords.y + @base_row
  end

  def populate_next_row
    @tiles[-COLUMNS, COLUMNS].each do |tile|
      tile.type = @tilegen.sample
      tile.ground_unit = nil
      tile.air_unit = nil

      if Random.rand(1.0) < 0.05
        unit_type = Kernel.const_get(@enemygen.sample)
        if (unit_type.ground_unit? && tile.type == :tile_ground) ||
           (unit_type.air_unit? && tile.type == :tile_mountain)
          # If the unit type doesn't match the tile type, just don't spawn it. 
          unit = unit_type.new(:enemy, tile)
          tile.ground_unit = unit if unit.ground_unit?
          tile.air_unit = unit if unit.air_unit?
        end
      end
    end
  end

  def update
    case @status
    when :scroll
      @transition_time += $window.milliseconds_since_last_tick

      if @transition_time > TRANSITION_TIME
        # The transition has finished
        @status = :default
        @transition_time = 0
        @draw_offset = 0
        #@tiles.rotate!(COLUMNS)

        @base_row += 1
        #populate_next_row

        # Friendly units run first.
        # TODO: Only run units on screen?
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
        @tiles[(row + @base_row) * COLUMNS + col].draw(
          col * @tile_width,
          BOARD_HEIGHT - (row + 1) * @tile_height + @draw_offset,
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

    # Move friendly ground units up the board (they stay at the same position
    # on the screen)
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

  def mouse_pos_to_tile(mouse_pos)
    get_tile(mouse_pos_to_tile_coords(mouse_pos))
  end

  def get_tile(tile_coord)
    @tiles[@base_row + tile_coord.y * COLUMNS + tile_coord.x]
  end

  def add_unit(unit, tile_coord)
    tile = get_tile(tile_coord)

    tile.ground_unit = unit if unit.ground_unit?
    tile.air_unit = unit if unit.air_unit?
    unit.tile = tile
  end

  def move_legal?(unit, to_coord)
    # TODO: unit move patterns etc
    return false if unit.ground_unit? && !tile_ground_empty?(to_coord)
    return false if unit.air_unit? && !tile_air_empty?(to_coord)
    return true
  end

  def move_unit(unit, to_coord)
    from_tile = unit.tile
    to_tile = get_tile(to_coord)

    if unit.air_unit?
      from_tile.air_unit = nil
      to_tile.air_unit = unit
    else
      from_tile.ground_unit = nil
      to_tile.ground_unit = unit
    end
    
    unit.tile = to_tile
  end

  def get_friendly_unit(tile_coord)
    unit = get_tile(tile_coord).air_unit
    if unit.nil? || !unit.friendly?
      unit = get_tile(tile_coord).ground_unit
    end

    if !unit.nil? && !unit.friendly?
      unit = nil
    end

    unit
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
    tile_coord.y - @base_row > @frontline
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
