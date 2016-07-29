require 'logger'

# Drawing order
module ZOrder
  MAP, UNIT, EFFECT, HUD = *0..3
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

class Text < Chingu::Text
  def draw(text=nil)
    @text = text if !text.nil?
    super()
  end
end
