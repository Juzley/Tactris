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
      mouse_wheel_up: lambda {
        if @board.base_row + Board::VISIBLE_ROWS < @board.rows 
          @board.base_row += 1
        end
      }, 
      mouse_wheel_down: lambda {@board.base_row -= 1 if @board.base_row > 0},
      e: lambda {pop_game_state},
    }

    def draw
      @board.draw
    end
  end
end
