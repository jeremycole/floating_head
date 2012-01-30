require 'appscript'

class SkypeEvents
  attr_accessor :skype

  CALL_PROPERTIES = [
    "TIMESTAMP",
    "PARTNER_HANDLE",
    "PARTNER_DISPNAME",
    "TYPE",
    "STATUS",
    "VIDEO_STATUS",
    "FAILUREREASON",
    "DURATION",
  ]

  CHAT_PROPERTIES = [
    "NAME",
    "TIMESTAMP",
    "ADDER",
    "STATUS",
    "POSTERS",
    "MEMBERS",
    "TOPIC",
    "RECENTCHATMESSAGES",
    "ACTIVEMEMBERS",
    "FRIENDLYNAME",
  ]

  CHATMESSAGE_PROPERTIES = [
    "CHATNAME",
    "TIMESTAMP",
    "FROM_HANDLE",
    "FROM_DISPNAME",
    "TYPE",
    "USERS",
    "LEAVEREASON",
    "BODY",
    "STATUS",
  ]

  def initialize(script_name)
    @skype = Appscript.app("Skype.app")
    @script_name = script_name
  end
  
  def command(command_text)
    skype.send_ :script_name => @script_name, :command => command_text
  end

  # -> "SEARCH ACTIVECALLS"
  # <- "CALLS <call1>[, <call2>]
  def api_search_activecalls
    result_pattern = /CALLS (.*)/
    result = command("SEARCH ACTIVECALLS")
    unless calls_match = result_pattern.match(result)
      return nil
    end
    
    calls_match[1].split(/,\s*/)
  end

  # -> "GET CALL <call> <property>"
  # <- "CALL <call> <property> <content>"
  def api_get_call_property(call, property)
    result_pattern = /CALL (\S+) (\S+) (.*)/
    result = command("GET CALL #{call} #{property}")
    unless call_property_match = result_pattern.match(result)
      return nil
    end

    value = call_property_match[3]
    case property
    when "TIMESTAMP"
      Time.at(value.to_i)
    else
      value
    end
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
      return nil
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
    result_pattern = /CHAT (\S+) (\S+) (.*)/
    result = command("GET CHAT #{chat} #{property}")
    unless chat_property_match = result_pattern.match(result)
      return nil
    end

    value = chat_property_match[3]
    case property
    when "TIMESTAMP"
      Time.at(value.to_i)
    when "RECENTCHATMESSAGES"
      value.split(/,\s*/)
    when "MEMBERS", "ACTIVEMEMBERS"
      value.split(/\s+/)
    else
      value
    end
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
    result_pattern = /MESSAGE (\S+) (\S+) (.*)/
    result = command("GET CHATMESSAGE #{chatmessage} #{property}")
    unless chatmessage_property_match = result_pattern.match(result)
      return nil
    end
    
    value = chatmessage_property_match[3]
    case property
    when "TIMESTAMP"
      Time.at(value.to_i)
    else
      value
    end
  end
  
  # Helper to loop over valid properties and get them all.
  def api_get_chatmessage(chatmessage)
    CHATMESSAGE_PROPERTIES.inject({"_id" => chatmessage}) do |result_hash, property|
      result_hash[property] = 
        api_get_chatmessage_property(chatmessage, property)
      result_hash
    end
  end

  def api_set_chatmessage_read(chatmessage)
    result_pattern = /MESSAGE (\S+) STATUS READ/
    result = command("SET CHATMESSAGE #{chatmessage} SEEN") # Yes, seen.
    !!result_pattern.match(result)
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

  def each_unread_chatmessage
    unless block_given?
      return Enumerable::Enumerator.new(self, :each_unread_chatmessage)
    end

    api_search_recentchats.each do |chat_id|
      chat = api_get_chat(chat_id)
      chat["RECENTCHATMESSAGES"].each do |chatmessage_id|
        chatmessage = api_get_chatmessage(chatmessage_id)
        if chatmessage["STATUS"] == "RECEIVED"
          yield chat, chatmessage
          api_set_chatmessage_read(chatmessage_id)
        end
      end
    end
  end
end
