# frozen_string_literal: true

module KubeMQ
  # Metadata about a KubeMQ channel returned by {BaseClient#list_channels}.
  #
  # @example
  #   channels = client.list_channels(channel_type: KubeMQ::ChannelType::EVENTS)
  #   channels.each do |ch|
  #     puts "#{ch.name} active=#{ch.active?} in=#{ch.incoming} out=#{ch.outgoing}"
  #   end
  #
  # @see BaseClient#list_channels
  # @see ChannelType
  class ChannelInfo
    # @!attribute [r] name
    #   @return [String] channel name
    # @!attribute [r] type
    #   @return [String] channel type (one of {ChannelType} constants)
    # @!attribute [r] last_activity
    #   @return [Integer] Unix timestamp of the last activity on this channel
    # @!attribute [r] is_active
    #   @return [Boolean] whether the channel currently has active subscribers
    # @!attribute [r] incoming
    #   @return [Integer] total number of incoming messages
    # @!attribute [r] outgoing
    #   @return [Integer] total number of outgoing messages
    attr_reader :name, :type, :last_activity, :is_active, :incoming, :outgoing

    # Creates a new ChannelInfo instance.
    #
    # @param name [String] channel name
    # @param type [String] channel type (one of {ChannelType} constants)
    # @param last_activity [Integer] Unix timestamp of last activity (default: +0+)
    # @param is_active [Boolean] whether the channel has active subscribers (default: +false+)
    # @param incoming [Integer] total incoming message count (default: +0+)
    # @param outgoing [Integer] total outgoing message count (default: +0+)
    def initialize(name:, type:, last_activity: 0, is_active: false, incoming: 0, outgoing: 0)
      @name = name
      @type = type
      @last_activity = last_activity
      @is_active = is_active
      @incoming = incoming
      @outgoing = outgoing
    end

    # Returns whether the channel currently has active subscribers.
    #
    # @return [Boolean]
    def active?
      @is_active
    end

    # Constructs a {ChannelInfo} from a parsed JSON hash.
    #
    # Accepts both camelCase (from the broker REST API) and snake_case keys.
    #
    # @api private
    # @param hash [Hash] parsed JSON hash with channel metadata
    # @return [ChannelInfo]
    def self.from_json(hash)
      is_active_val = if hash.key?('isActive') then hash['isActive']
                      elsif hash.key?('is_active') then hash['is_active']
                      elsif hash.key?(:is_active) then hash[:is_active]
                      else false
                      end

      new(
        name: hash['name'] || hash[:name] || '',
        type: hash['type'] || hash[:type] || '',
        last_activity: hash['lastActivity'] || hash['last_activity'] || hash[:last_activity] || 0,
        is_active: is_active_val,
        incoming: hash['incoming'] || hash[:incoming] || 0,
        outgoing: hash['outgoing'] || hash[:outgoing] || 0
      )
    end

    # Returns a human-readable summary of the channel information.
    #
    # @return [String]
    def to_s
      "ChannelInfo(name=#{@name}, type=#{@type}, active=#{active?})"
    end
  end
end
