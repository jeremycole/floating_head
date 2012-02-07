require 'skype_events'
require 'serial_pan_tilt'
require 'sqlite3'
require 'ostruct'
require 'getoptlong'
require 'osax'

class FloatingHead
  attr_accessor :skype_events
  attr_accessor :camera
  attr_accessor :data

  def initialize
    @options = OpenStruct.new
    parse_arguments

    @data = SQLite3::Database.new(@options.data_file)
    create_locations_table

    @osax = OSAX.osax

    @skype_events = SkypeEvents.new("floating_head")
    @camera = SerialPanTilt.new(@options.device)
  end

  def usage(exit_code)
    puts
    puts "Usage: floating_head -d <device> [options]"
    puts
    puts "  --device <device>, -d <device>"
    puts "    The serial port device to use (required)."
    puts
    puts "  --data-file <file>, -f <file>"
    puts "    The data file to use (default floating_head.db)."
    puts
    puts "  --limits <limits>, -l <limits>"
    puts "    The pan/tilt limits to enforce, comma-separated list of:"
    puts "    pan min, pan max, tilt min, tilt max, e.g. '35,125,40,110'."
    puts
    puts "  --poll <seconds>, -p <seconds>"
    puts "    The poll interval to check for new unread messages in Skype."
    puts "    More aggressive polling may make Skype slow, but lazier polling"
    puts "    makes the camera less responsive. (default 0.1 seconds)"
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
    @options.poll         = 0.1

    getopt = GetoptLong.new(
      [ "--help",             "-?",     GetoptLong::NO_ARGUMENT ],
      [ "--device",           "-d",     GetoptLong::REQUIRED_ARGUMENT ],
      [ "--data-file",        "-f",     GetoptLong::REQUIRED_ARGUMENT ],
      [ "--limits",           "-l",     GetoptLong::REQUIRED_ARGUMENT ],
      [ "--poll",             "-p",     GetoptLong::REQUIRED_ARGUMENT ]
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
            @options.pan_min    = limits[0].to_i
            @options.pan_max    = limits[1].to_i
            @options.tilt_min   = limits[2].to_i
            @options.tilt_max   = limits[3].to_i
          else
            raise "Incorrect limits specified"
          end
        when "--poll"
          @options.poll = arg.to_f
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

  def reply(chat, message)
    puts "Replying with:\n#{message}\n"
    skype_events.api_chatmessage(chat["_id"], message) if chat
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
      "  !vol <percent> | Set the output (speaker) volume to <percent>.",
      "  !mic <percent> | Set the input (microphone) volume to <percent>.",
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
    return "pan < (#{@options.pan_min})"    if pan.to_i  < @options.pan_min
    return "pan > (#{@options.pan_max})"    if pan.to_i  > @options.pan_max
    return "tilt < (#{@options.tilt_min})"  if tilt.to_i < @options.tilt_min
    return "tilt > (#{@options.tilt_max})"  if tilt.to_i > @options.tilt_max
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

  def set_device_volume(chat, device, level)
    if level >= 0 and level <= 100
      @osax.set_volume device => level
      reply(chat, "Volume (#{device}) set to #{level}.")
    else
      reply(chat, "Volume (#{device}) must be between 0 and 100!")
    end
  end

  def vol(chat, level)
    puts "VOL: #{level}"
    set_device_volume(chat, :output_volume, level.to_i)
  end

  def mic(chat, level)
    puts "MIC: #{level}"
    set_device_volume(chat, :input_volume, level.to_i)
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
    when m = /^!vol (\d+)/.match(message)
      vol(chat, m[1])
    when m = /^!mic (\d+)/.match(message)
      mic(chat, m[1])
    else
      reply(chat, "Didn't understand '#{message}'! Try '!help' for help.")
    end
  end

  def run
    # Throw away any unread messages before we get started, in case there
    # are commands in there that we missed.
    begin
      skype_events.each_unread_chatmessage {}
    rescue Appscript::CommandError
    end

    while true
      sleep @options.poll
      next unless partner = skype_events.active_call_partner
      begin
        skype_events.each_unread_chatmessage(partner) do |chat, chatmessage|
          handle  = chatmessage['FROM_HANDLE']
          message = chatmessage['BODY']
          unless skype_events.active_call_partner? handle
            puts "Got message from #{handle}, who is not my active call partner!"
            next
          end
          puts "Message from #{handle}: #{message}"
          handle_command(chat, message)
        end
      rescue Appscript::CommandError
        puts "Skype doesn't seem to be running. Maybe it crashed? Waiting."
        sleep 5
      end
    end
  end
end