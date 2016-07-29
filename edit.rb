require 'rubygems'
require 'chingu'

class Edit < Chingu::GameState
  include Logging

  def initialize(board)
    super()
    @board = board
  end
end
