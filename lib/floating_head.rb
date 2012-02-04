require 'skype_events'
require 'serial_pan_tilt'
require 'sqlite3'
require 'ostruct'
require 'getoptlong'

class FloatingHead
  attr_accessor :skype_events
  attr_accessor :camera
  attr_accessor :data

  def initialize
    @options = OpenStruct.new
    parse_arguments

    @data = SQLite3::Database.new(@options.data_file)
    create_locations_table

    @skype_events = SkypeEvents.new("floating_head")
    @camera = SerialPanTilt.new(@options.device)
  end

  def usage(exit_code)
    puts
    puts "Usage: floating_head -d <device> [-f <data-file>] [-l <limits>]"
    puts
    puts "  --device, -d"
    puts "    The serial port device to use (required)."
    puts
    puts "  --data-file, -f"
    puts "    The data file to use (default floating_head.db)."
    puts
    puts "  --limits, -l"
    puts "    The pan/tilt limits to enforce, comma-separated list of:"
    puts "    pan min, pan max, tilt min, tilt max, e.g. '35,125,40,110'."
    puts
    exit exit_code
  end

  def parse_arguments
    @options.device       = nil
    @options.data_file    = "floating_head.db"
    @options.pan_min      = 60
    @options.pan_max      = 120
    @options.tilt_min     = 60
    @options.tilt_max     = 120

    getopt = GetoptLong.new(
      [ "--help",             "-?",     GetoptLong::NO_ARGUMENT ],
      [ "--device",           "-d",     GetoptLong::REQUIRED_ARGUMENT ],
      [ "--data-file",        "-f",     GetoptLong::REQUIRED_ARGUMENT ],
      [ "--limits",           "-l",     GetoptLong::REQUIRED_ARGUMENT ]
    )
    
    getopt.each do |opt, arg|
      case opt
        when "--help"
          usage 0
        when "--device"
          @options.device = arg
        when "--data-file"
          @options.data_file = arg
        when "--limits"
          if (limits = arg.split(",")).size == 4
            @options.pan_min    = limits[0]
            @options.pan_max    = limits[1]
            @options.tilt_min   = limits[2]
            @options.tilt_max   = limits[3]
          else
            raise "Incorrect limits specified"
          end
      end
    end
    
    if @options.device.nil?
      raise "device not set"
    end
    
    if @options.data_file.nil?
      raise "data-file not set"
    end
    
    self
  end

  def create_locations_table
    unless @data.query("SELECT name FROM sqlite_master WHERE type='table'").to_a.flatten.include? "locations"
      @data.query("CREATE TABLE locations (name varchar(30), pan int, tilt int)")
    end
  end

  def active_call_partner?(handle)
    return nil unless call = skype_events.each_call.first
    call["PARTNER_HANDLE"] == handle
  end

  def reply(chat, message)
    puts "Replying with:\n#{message}\n"
    skype_events.api_chatmessage(chat["_id"], message)
  end

  def help(chat)
    help_message = [
      "The following commands are understood:",
      "  !help | Show this help.",
      "  !list | List all saved camera positions.",
      "  !save <name> | Save the current camera position as <name>.",
      "  !erase <name> | Erase the saved camera position as <name>.",
      "  !pos <pan>, <tilt> | Position the camera at <pan>, <tilt> degrees.",
      "  !left <deg> | Pan the camera <deg> degrees left.",
      "  !right <deg> | Pan the camera <deg> degrees right.",
      "  !down <deg> | Tilt the camera <deg> degrees down.",
      "  !up <deg> | Tilt the camera <deg> degrees up.",
      "  !go <name> | Go to saved camera position <name>.",
      "  @<name> | Alias for !go <name>.",
      "",
    ].join("\n")
    
    reply(chat, help_message)
  end

  def list(chat)
    locations = data.execute("SELECT * FROM locations")
    if locations.empty?
      reply(chat, "No locations known!")
      return
    end

    location_reply = "The following locations are known:\n"
    locations.each do |row|
      location_reply << "  #{row[0]} (#{row[1]}, #{row[2]})\n"
    end
    reply(chat, location_reply)
  end

  def save(chat, name, pan, tilt)
    puts "SAVE: #{name}, #{pan}, #{tilt}"
    result = data.execute("INSERT INTO locations (name, pan, tilt) VALUES (?, ?, ?)", name, pan, tilt)
    if result
      reply(chat, "Saved '#{name}' as (#{pan}, #{tilt})!")
    else
      reply(chat, "Failed to save '#{name}'!")
    end
  end

  def erase(chat, name)
    puts "ERASE: #{name}"
    result = data.execute("DELETE FROM locations WHERE name = ?", name)
    if result
      reply(chat, "Erased '#{name}'!")
    else
      reply(chat, "Failed to erase '#{name}'!")
    end    
  end

  def limits_exceeded?(pan, tilt)
    return "pan < (#{@options.pan_min})"    if pan  < @options.pan_min
    return "pan > (#{@options.pan_max})"    if pan  > @options.pan_max
    return "tilt < (#{@options.tilt_min})"  if tilt < @options.tilt_min
    return "tilt > (#{@options.tilt_max})"  if tilt > @options.tilt_max
    nil
  end

  def pos(chat, pan, tilt)
    if reason = limits_exceeded?(pan, tilt)
      reply(chat, "Limits exceeded (#{reason})! Try to be reasonable.")
    else
      camera.pan_tilt(pan, tilt)
      reply(chat, "Going to (#{pan}, #{tilt})!")
    end
  end

  def go(chat, name)
    puts "GO: #{name}"
    location = data.get_first_row("SELECT * FROM locations WHERE name = ?", name)
    unless location
      reply(chat, "Location '#{name}' is not known!")
      return
    end
    db_name, pan, tilt = location
    
    pos(chat, pan, tilt)
  end

  def left(chat, degrees)
    pos(chat, camera.pan_position-degrees.to_i, camera.tilt_position)
  end

  def right(chat, degrees)
    pos(chat, camera.pan_position+degrees.to_i, camera.tilt_position)
  end

  def down(chat, degrees)
    pos(chat, camera.pan_position, camera.tilt_position-degrees.to_i)
  end

  def up(chat, degrees)
    pos(chat, camera.pan_position, camera.tilt_position+degrees.to_i)
  end

  def handle_command(chat, message)
    case
    when m = /^!help/.match(message)
      help(chat)
    when m = /^!list/.match(message)
      list(chat)
    when m = /^!save (\S+)/.match(message)
      pan, tilt = camera.position
      save(chat, m[1], pan, tilt)
    when m = /^!erase (\S+)/.match(message)
      erase(chat, m[1])
    when m = /^!go (\S+)/.match(message)
      go(chat, m[1])
    when m = /^@(\S+)/.match(message)
      go(chat, m[1])
    when m = /^!pos (\d+), *(\d+)/.match(message)
      pos(chat, m[1], m[2])
    when m = /^!left (\d+)/.match(message)
      left(chat, m[1])
    when m = /^!right (\d+)/.match(message)
      right(chat, m[1])
    when m = /^!down (\d+)/.match(message)
      down(chat, m[1])
    when m = /^!up (\d+)/.match(message)
      up(chat, m[1])
    else
      reply(chat, "Didn't understand '#{message}'! Try '!help' for help.")
    end
  end

  def run
    # Throw away any unread messages before we get started, in case there
    # are commands in there that we missed.
    skype_events.each_unread_chatmessage {}

    while true
      sleep 0.1
      skype_events.each_unread_chatmessage do |chat, chatmessage|
        handle  = chatmessage['FROM_HANDLE']
        message = chatmessage['BODY']
        unless active_call_partner? handle
          puts "Got message from #{handle}, who is not my active call partner!"
          next
        end
        puts "Message from #{handle}: #{message}"
        handle_command(chat, message)
      end
    end
  end
end