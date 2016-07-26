require_relative 'util.rb'

class Unit
  attr_accessor :tile
  attr_reader :place_ap, :move_ap

  def initialize(tile, type)
    @type = type
    @tile = tile
    @place_ap = 0
    @move_ap = 0
    @state = :idle
  end

  def draw(x, y, width, height)
    @image.draw_size(x, y, ZOrder::UNIT, width, height)
  end

  def friendly?
    @type == :friendly
  end

  def enemy?
    @type == :enemy
  end

  def ground_unit?
    true
  end

  def air_unit?
    !ground_unit?
  end

  def hits_ground?
    true
  end

  def hits_air?
    false
  end

  def dead?
    @state == :dead
  end

  def update
    @image = @animation[@state].next

    # If this unit is dead, unlink it from the board once the
    # death animation is finished
    if @state == :dead && @animation[@state].last_frame?
      @tile.ground_unit = nil if self.ground_unit?
      @tile.air_unit = nil if self.air_unit?
    end
    @state = :idle if @state == :fire && @animation[@state].last_frame?
  end

  def viable_target(unit)
    if unit.nil? || unit.dead?
      false
    elsif unit.enemy? == self.enemy?
      false
    elsif unit.ground_unit? && !self.hits_ground?
      false
    elsif unit.air_unit? && !self.hits_air
      false
    else
      true
    end
  end

  def run
  end

  def damage
    @state = :dead
  end

  def to_s
    if enemy? then 'Enemy ' else 'Friendly ' end + self.class.to_s
  end
end

class Tank < Unit
  FIRE_PATTERN = [[-1, 1], [0, 1], [1, 1]]

  def initialize(tile, type)
    super(tile, type)

    @animation = Chingu::Animation.new(file: "droid_11x15.bmp")
    @animation.frame_names = { dead: 0..5, fire: 6..7, idle: 8..9  }
    @animation[:dead].loop = false
    @animation[:fire].loop = false
    @image = @animation[:idle].first
  end

  def run
    orientation = if enemy? then :down else :up end
    @tile.walk_surrounding(FIRE_PATTERN, orientation) do |tile|
      tile.each_unit do |unit|
        if viable_target(unit)
          @state = :fire
          unit.damage()
          break 2
        end
      end
    end
  end
end

class Artillery < Unit
  FIRE_PATTERN = [[0, 2], [0, 3]]

  def initialize(tile, type)
    super(tile, type)

    @animation = Chingu::Animation.new(file: "droid_11x15.bmp")
    @animation.frame_names = { dead: 0..5, fire: 6..7, idle: 8..9  }
    @animation[:dead].loop = false
    @animation[:fire].loop = false
    @image = @animation[:idle].first
  end

  def draw
    @image.draw_size(x, y, ZOrder::UNIT, width, height, color = 0xff0000ff)
  end

  def run
    orientation = if enemy? then :down else :up end
    @tile.walk_surrounding(FIRE_PATTERN, orientation) do |tile|
      tile.each_unit do |unit|
        if viable_target(unit)
          @state = :fire
          unit.damage()
          break 2
        end
      end
    end
  end
end

class Bomber < Unit
  def ground_unit?
    false
  end

  def initialize(tile, type)
    super(tile, type)

    @animation = Chingu::Animation.new(file: "droid_11x15.bmp")
    @animation.frame_names = { dead: 0..5, fire: 6..7, idle: 8..9  }
    @animation[:dead].loop = false
    @animation[:fire].loop = false
    @image = @animation[:idle].first
  end

  def draw
    @image.draw_size(x, y, ZOrder::UNIT, width, height, color = 0x00ff00ff)
  end

  def run
    orientation = if enemy? then :down else :up end
    @tile.each_unit do |unit|
      if viable_target(unit)
        @state = :fire
        unit.damage()
        break 2
      end
    end
  end
end
