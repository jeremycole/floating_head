require 'appscript'

class SkypeEvents
  attr_accessor :skype

  CALL_PROPERTIES = [
    "STATUS",
    "TIMESTAMP",
    "PARTNER_HANDLE",
    "PARTNER_DISPNAME",
    "TYPE",
    "VIDEO_STATUS",
    "FAILUREREASON",
    "DURATION",
  ]

  CHAT_PROPERTIES = [
    "STATUS",
    "TIMESTAMP",
    "NAME",
    "ADDER",
    "POSTERS",
    "MEMBERS",
    "TOPIC",
    "RECENTCHATMESSAGES",
    "ACTIVEMEMBERS",
    "FRIENDLYNAME",
  ]

  CHATMESSAGE_PROPERTIES = [
    "STATUS",
    "TIMESTAMP",
    "CHATNAME",
    "FROM_HANDLE",
    "FROM_DISPNAME",
    "TYPE",
    "USERS",
    "LEAVEREASON",
    "BODY",
  ]

  def initialize(script_name)
    @cache = {}
    @skype = Appscript.app("Skype.app")
    @script_name = script_name
  end
  
  def command(command_text)
    #puts "Skype: #{command_text}"
    skype.send_ :script_name => @script_name, :command => command_text
  end

  # -> "GET VIDEO_IN"
  # <- "VIDEO_IN <device>"
  def api_get_video_in
    result_pattern = /VIDEO_IN (.*)/
    result = command("GET VIDEO_IN")
    unless video_in_match = result_pattern.match(result)
      return nil
    end

    video_in_match[1]
  end

  # -> "SET VIDEO_IN <device>"
  # <- "VIDEO_IN <device>"
  def api_set_video_in(device)
    result_pattern = /VIDEO_IN (.*)/
    result = command("SET VIDEO_IN #{device}")
    unless video_in_match = result_pattern.match(result)
      return nil
    end

    video_in_match[1] == device
  end

  # -> "SEARCH ACTIVECALLS"
  # <- "CALLS <call1>[, <call2>]
  def api_search_activecalls
    result_pattern = /CALLS (.*)/
    result = command("SEARCH ACTIVECALLS")
    unless calls_match = result_pattern.match(result)
      return []
    end
    
    calls_match[1].split(/,\s*/)
  end

  # -> "GET CALL <call> <property>"
  # <- "CALL <call> <property> <content>"
  def api_get_call_property(call, property)
    cache_key = "call:#{call}:#{property}"
    unless ["STATUS"].include? property
      return @cache[cache_key] if @cache.include? cache_key
    end

    result_pattern = /CALL (\S+) (\S+) (.*)/
    result = command("GET CALL #{call} #{property}")
    unless call_property_match = result_pattern.match(result)
      return nil
    end

    value = call_property_match[3]
    case property
    when "TIMESTAMP"
      value = Time.at(value.to_i)
    end
    
    @cache[cache_key] = value 
  end

  # Helper to loop over valid properties and get them all.
  def api_get_call(call)
    CALL_PROPERTIES.inject({"_id" => call}) do |result_hash, property|
      result_hash[property] = api_get_call_property(call, property)
      result_hash
    end
  end

  # -> "SEARCH RECENTCHATS"
  # <- "CHATS <chat1>[, <chat2>]"
  def api_search_recentchats
    result_pattern = /CHATS (.*)/
    result = command("SEARCH RECENTCHATS")
    unless chats_match = result_pattern.match(result)
      return []
    end

    chats_match[1].split(/,\s*/)
  end

  # -> "CHATMESSAGE <chat> <message>
  # <- "MESSAGE <chatmessage> STATUS <status>"
  def api_chatmessage(chat, message)
    result_pattern = /MESSAGE (\S+) STATUS (\S+)/
    result = command("CHATMESSAGE #{chat} #{message}")
    unless message_match = result_pattern.match(result)
      return nil
    end
    message_match[2]
  end

  # -> "GET CHAT <chat> <property>"
  # <- "CHAT <chat> <property> <content>"
  def api_get_chat_property(chat, property)
    cache_key = "chat:#{chat}:#{property}"
    unless ["STATUS", "RECENTCHATMESSAGES"].include? property
      return @cache[cache_key] if @cache.include? cache_key
    end

    result_pattern = /CHAT (\S+) (\S+) (.*)/
    result = command("GET CHAT #{chat} #{property}")
    unless chat_property_match = result_pattern.match(result)
      return nil
    end

    value = chat_property_match[3]
    case property
    when "TIMESTAMP"
      value = Time.at(value.to_i)
    when "RECENTCHATMESSAGES"
      value = value.split(/,\s*/)
    when "MEMBERS", "ACTIVEMEMBERS"
      value = value.split(/\s+/)
    end

    @cache[cache_key] = value
  end

  # Helper to loop over valid properties and get them all.
  def api_get_chat(chat)
    CHAT_PROPERTIES.inject({"_id" => chat}) do |result_hash, property|
      result_hash[property] = api_get_chat_property(chat, property)
      result_hash
    end
  end
  
  # -> GET CHATMESSAGE <chatmessage> <property>
  # <- MESSAGE <chatmessage> <property> <content>
  def api_get_chatmessage_property(chatmessage, property)
    cache_key = "chatmessage:#{chatmessage}:#{property}"
    if property != "STATUS" or 
      (property == "STATUS" and ["READ", "SENT"].include? @cache[cache_key])
      return @cache[cache_key] if @cache.include? cache_key
    end

    result_pattern = /MESSAGE (\S+) (\S+) (.*)/
    result = command("GET CHATMESSAGE #{chatmessage} #{property}")
    unless chatmessage_property_match = result_pattern.match(result)
      return nil
    end
    
    value = chatmessage_property_match[3]
    case property
    when "TIMESTAMP"
      value = Time.at(value.to_i)
    end

    @cache[cache_key] = value
  end
  
  # Helper to loop over valid properties and get them all.
  def api_get_chatmessage(chatmessage)
    CHATMESSAGE_PROPERTIES.inject({"_id" => chatmessage}) do |result_hash, property|
      result_hash[property] = 
        api_get_chatmessage_property(chatmessage, property)
      result_hash
    end
  end

  def api_get_chatmessage_unread?(chatmessage)
    # Unread messages have status "RECEIVED".
    "RECEIVED" == api_get_chatmessage_property(chatmessage, "STATUS")
  end

  def api_set_chatmessage_read(chatmessage)
    result_pattern = /MESSAGE (\S+) STATUS READ/
    result = command("SET CHATMESSAGE #{chatmessage} SEEN") # Yes, seen.
    !!result_pattern.match(result)
  end

  def active_call_partner
    return nil unless call = each_call.first
    call["PARTNER_HANDLE"]
  end

  def active_call_partner?(handle)
    active_call_partner == handle
  end

  def each_call
    unless block_given?
      return Enumerable::Enumerator.new(self, :each_call)
    end

    api_search_activecalls.each do |call_id|
      yield api_get_call(call_id)
    end
  end

  def each_chat
    unless block_given?
      return Enumerable::Enumerator.new(self, :each_chat)
    end

    api_search_recentchats.each do |chat_id|
      yield api_get_chat(chat_id)
    end
  end

  def each_unread_chatmessage(from_handle=nil)
    unless block_given?
      return Enumerable::Enumerator.new(self, :each_unread_chatmessage)
    end

    api_search_recentchats.each do |chat_id|
      # Skip this chat completely if it's not with the provided handle.
      next if from_handle and not /##{from_handle}\//.match(chat_id)

      chat = api_get_chat(chat_id)
      chat["RECENTCHATMESSAGES"].each do |chatmessage_id|
        if api_get_chatmessage_unread? chatmessage_id
          # Only get the full chatmessage for unread messages, since the
          # Skype API is so terrible and slow.
          chatmessage = api_get_chatmessage(chatmessage_id)
          yield chat, chatmessage
          api_set_chatmessage_read(chatmessage_id)
        end
      end
    end
  end
end
