module Houston
  APPLE_PRODUCTION_GATEWAY_URI = "apn://gateway.push.apple.com:2195"
  APPLE_PRODUCTION_FEEDBACK_URI = "apn://feedback.push.apple.com:2196"

  APPLE_DEVELOPMENT_GATEWAY_URI = "apn://gateway.sandbox.push.apple.com:2195"
  APPLE_DEVELOPMENT_FEEDBACK_URI = "apn://feedback.push.apple.com:2196"

  class Client
    attr_accessor :gateway_uri, :feedback_uri, :certificate, :passphrase, :timeout

    def initialize
      @gateway_uri = ENV['APN_GATEWAY_URI']
      @feedback_uri = ENV['APN_FEEDBACK_URI']
      @certificate = ENV['APN_CERTIFICATE']
      @passphrase = ENV['APN_CERTIFICATE_PASSPHRASE']
      @timeout = ENV['APN_TIMEOUT'] || 0.5
    end

    def self.development
      client = self.new
      client.gateway_uri = APPLE_DEVELOPMENT_GATEWAY_URI
      client.feedback_uri = APPLE_DEVELOPMENT_FEEDBACK_URI
      client
    end

    def self.production
      client = self.new
      client.gateway_uri = APPLE_PRODUCTION_GATEWAY_URI
      client.feedback_uri = APPLE_PRODUCTION_FEEDBACK_URI
      client
    end

    def push(*notifications)
      return if notifications.empty?

      notifications.flatten!
      error = nil

      Connection.open(connection_options_for_endpoint(:gateway)) do |connection, socket|
        notifications.each_with_index do |notification, index|
          next unless notification.kind_of?(Notification)
          next if notification.sent?

          notification.id = index

          connection.write(notification.message)
          notification.mark_as_sent!

          break if notifications.count == 1 || notification == notifications.last

          read_socket, write_socket = IO.select([connection], [connection], [connection], nil)
          if (read_socket && read_socket[0])
            error = connection.read(6)
            break
          end
        end

        return if notifications.count == 1

        unless error
          read_socket, write_socket = IO.select([connection], nil, [connection], timeout)
          if (read_socket && read_socket[0])
            error = connection.read(6)
          end
        end
      end

      if error
        command, status, index = error.unpack("cci")
        notifications.slice!(0..index)
        notifications.each(&:mark_as_unsent!)
        push(*notifications)
      end
    end

    def devices
      devices = []

      Connection.open(connection_options_for_endpoint(:feedback)) do |connection, socket|
        while line = connection.read(38)
          feedback = line.unpack('N1n1H140')            
          token = feedback[2].scan(/.{0,8}/).join(' ').strip
          devices << token if token
        end
      end

      devices
    end

    private

      def connection_options_for_endpoint(endpoint = :gateway)
        uri = case endpoint
                when :gateway then URI(@gateway_uri)
                when :feedback then URI(@feedback_uri)
                else
                  raise ArgumentError
              end

        {
          certificate: @certificate,
          passphrase: @passphrase,
          host: uri.host,
          port: uri.port
        }
      end
  end
end
