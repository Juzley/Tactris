require 'rubygems'
require 'chingu'
require_relative 'game.rb'

include Gosu
include Chingu

class Edit < Chingu::GameState
  include Logging

  def initialize(board)
    super()
    @board = board

    self.input = {
      e: lambda {pop_game_state(:setup => false)},
      s: lambda {self.save},
      left_mouse_button: lambda {self.edit_tile},
      mouse_wheel_up: lambda {
        if @board.base_row + Board::VISIBLE_ROWS < @board.rows 
          @board.base_row += 1
        end
      }, 
      mouse_wheel_down: lambda {@board.base_row -= 1 if @board.base_row > 0},
    }

    def draw
      @board.draw
    end

    def save
      File.open('temp.lvl', 'w') {|f| f.write(Marshal.dump(@board))}
    end

    def edit_tile
      tile = @board.mouse_pos_to_tile(Point.new($window.mouse_x,
                                                $window.mouse_y))

      cur_type_idx = Tile::TYPES.index(tile.type)
      next_type_idx = cur_type_idx + 1
      next_type_idx = 0 if next_type_idx == Tile::TYPES.length

      tile.type = Tile::TYPES[next_type_idx]
    end
  end
end
