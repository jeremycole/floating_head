require 'serialport'

class SerialPanTilt
  attr_accessor :device, :baudrate, :serial
  attr_reader :pan_position, :tilt_position
  
  def initialize(device, baudrate=9600)
    @device = device
    @baudrate = baudrate

    if device == "dummy"
      @serial = nil
    else
      @serial = SerialPort.new(device, baudrate)
    end
    
    @pan_position = nil
    @tilt_position = nil
    
    home
  end

  def write(string)
    if serial.nil?
      puts "Dummy write: #{string}"
    else
      serial.write(string)
    end
  end

  def pan(degrees)
    write("P#{degrees.to_i}\n")
    @pan_position = degrees
  end

  def tilt(degrees)
    write("T#{degrees.to_i}\n")
    @tilt_position = degrees
  end
  
  def pan_tilt(pan_degrees, tilt_degrees)
    pan(pan_degrees)
    tilt(tilt_degrees)
  end
  
  def home
    pan_tilt(90, 90)
  end

  def position
    [pan_position, tilt_position]
  end
end