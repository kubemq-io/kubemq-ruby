# frozen_string_literal: true

require 'prometheus/client'
require 'prometheus/client/formats/text'

module KubeMQBurnin
  # rubocop:disable Metrics/ModuleLength -- Prometheus metric registry surface
  module Metrics
    LATENCY_BUCKETS = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 5.0].freeze

    @registry = Prometheus::Client::Registry.new
    @mutex = Mutex.new

    class << self
      attr_reader :registry

      # 1. kubemq_burnin_messages_sent_total (Counter, labels: worker, channel)
      def messages_sent_total
        @messages_sent_total ||= register(:counter, :kubemq_burnin_messages_sent_total,
                                          'Total messages sent', labels: %i[worker channel])
      end

      # 2. kubemq_burnin_messages_received_total (Counter, labels: worker, channel)
      def messages_received_total
        @messages_received_total ||= register(:counter, :kubemq_burnin_messages_received_total,
                                              'Total messages received', labels: %i[worker channel])
      end

      # 3. kubemq_burnin_messages_sent_bytes_total (Counter, labels: worker, channel)
      def messages_sent_bytes_total
        @messages_sent_bytes_total ||= register(:counter, :kubemq_burnin_messages_sent_bytes_total,
                                                'Total bytes sent', labels: %i[worker channel])
      end

      # 4. kubemq_burnin_messages_received_bytes_total (Counter, labels: worker, channel)
      def messages_received_bytes_total
        @messages_received_bytes_total ||= register(:counter, :kubemq_burnin_messages_received_bytes_total,
                                                    'Total bytes received', labels: %i[worker channel])
      end

      # 5. kubemq_burnin_errors_total (Counter, labels: worker, error_type)
      def errors_total
        @errors_total ||= register(:counter, :kubemq_burnin_errors_total,
                                   'Total errors', labels: %i[worker error_type])
      end

      # 6. kubemq_burnin_send_duration_seconds (Histogram, labels: worker)
      def send_duration_seconds
        @send_duration_seconds ||= register(
          :histogram, :kubemq_burnin_send_duration_seconds,
          'Send latency', labels: %i[worker], buckets: LATENCY_BUCKETS
        )
      end

      # 7. kubemq_burnin_receive_duration_seconds (Histogram, labels: worker)
      def receive_duration_seconds
        @receive_duration_seconds ||= register(
          :histogram, :kubemq_burnin_receive_duration_seconds,
          'Receive latency', labels: %i[worker], buckets: LATENCY_BUCKETS
        )
      end

      # 8. kubemq_burnin_reconnections_total (Counter, labels: worker)
      def reconnections_total
        @reconnections_total ||= register(:counter, :kubemq_burnin_reconnections_total,
                                          'Reconnection count', labels: %i[worker])
      end

      # 9. kubemq_burnin_messages_pending (Gauge, labels: worker)
      def messages_pending
        @messages_pending ||= register(:gauge, :kubemq_burnin_messages_pending,
                                       'Pending messages', labels: %i[worker])
      end

      # 10. kubemq_burnin_worker_state (Gauge, labels: worker)
      def worker_state
        @worker_state ||= register(:gauge, :kubemq_burnin_worker_state,
                                   'Worker state (0=idle, 1=running, 2=stopped)', labels: %i[worker])
      end

      # 11. kubemq_burnin_send_rate (Gauge, labels: worker)
      def send_rate
        @send_rate ||= register(:gauge, :kubemq_burnin_send_rate,
                                'Current send rate (msg/s)', labels: %i[worker])
      end

      # 12. kubemq_burnin_receive_rate (Gauge, labels: worker)
      def receive_rate
        @receive_rate ||= register(:gauge, :kubemq_burnin_receive_rate,
                                   'Current receive rate (msg/s)', labels: %i[worker])
      end

      # 13. kubemq_burnin_ack_total (Counter, labels: worker)
      def ack_total
        @ack_total ||= register(:counter, :kubemq_burnin_ack_total,
                                'Total acks', labels: %i[worker])
      end

      # 14. kubemq_burnin_nack_total (Counter, labels: worker)
      def nack_total
        @nack_total ||= register(:counter, :kubemq_burnin_nack_total,
                                 'Total nacks', labels: %i[worker])
      end

      # 15. kubemq_burnin_requeue_total (Counter, labels: worker)
      def requeue_total
        @requeue_total ||= register(:counter, :kubemq_burnin_requeue_total,
                                    'Total requeues', labels: %i[worker])
      end

      # 16. kubemq_burnin_commands_executed_total (Counter, labels: worker)
      def commands_executed_total
        @commands_executed_total ||= register(:counter, :kubemq_burnin_commands_executed_total,
                                              'Commands executed', labels: %i[worker])
      end

      # 17. kubemq_burnin_commands_failed_total (Counter, labels: worker)
      def commands_failed_total
        @commands_failed_total ||= register(:counter, :kubemq_burnin_commands_failed_total,
                                            'Commands failed', labels: %i[worker])
      end

      # 18. kubemq_burnin_queries_executed_total (Counter, labels: worker)
      def queries_executed_total
        @queries_executed_total ||= register(:counter, :kubemq_burnin_queries_executed_total,
                                             'Queries executed', labels: %i[worker])
      end

      # 19. kubemq_burnin_queries_cache_hits_total (Counter, labels: worker)
      def queries_cache_hits_total
        @queries_cache_hits_total ||= register(:counter, :kubemq_burnin_queries_cache_hits_total,
                                               'Query cache hits', labels: %i[worker])
      end

      # 20. kubemq_burnin_uptime_seconds (Gauge, no labels)
      def uptime_seconds
        @uptime_seconds ||= register(:gauge, :kubemq_burnin_uptime_seconds, 'App uptime')
      end

      # 21. kubemq_burnin_connection_state (Gauge, labels: client)
      def connection_state
        @connection_state ||= register(:gauge, :kubemq_burnin_connection_state,
                                       'Connection state', labels: %i[client])
      end

      # 22. kubemq_burnin_buffer_size (Gauge, labels: worker)
      def buffer_size
        @buffer_size ||= register(:gauge, :kubemq_burnin_buffer_size,
                                  'Current buffer usage', labels: %i[worker])
      end

      # 23. kubemq_burnin_buffer_overflow_total (Counter, labels: worker)
      def buffer_overflow_total
        @buffer_overflow_total ||= register(:counter, :kubemq_burnin_buffer_overflow_total,
                                            'Buffer overflows', labels: %i[worker])
      end

      # 24. kubemq_burnin_channels_created_total (Counter, labels: type)
      def channels_created_total
        @channels_created_total ||= register(:counter, :kubemq_burnin_channels_created_total,
                                             'Channels created', labels: %i[type])
      end

      # 25. kubemq_burnin_channels_deleted_total (Counter, labels: type)
      def channels_deleted_total
        @channels_deleted_total ||= register(:counter, :kubemq_burnin_channels_deleted_total,
                                             'Channels deleted', labels: %i[type])
      end

      # 26. kubemq_burnin_channels_purged_total (Counter, labels: type)
      def channels_purged_total
        @channels_purged_total ||= register(:counter, :kubemq_burnin_channels_purged_total,
                                            'Channels purged', labels: %i[type])
      end

      def scrape
        Prometheus::Client::Formats::Text.marshal(registry)
      end

      def reset!
        @mutex.synchronize do
          @registry = Prometheus::Client::Registry.new
          instance_variables.each do |ivar|
            next if %i[@registry @mutex].include?(ivar)

            instance_variable_set(ivar, nil)
          end
        end
      end

      private

      def register(type, name, docstring, labels: [], buckets: nil)
        @mutex.synchronize do
          existing = @registry.get(name)
          return existing if existing

          case type
          when :counter
            @registry.counter(name, docstring: docstring, labels: labels)
          when :gauge
            @registry.gauge(name, docstring: docstring, labels: labels)
          when :histogram
            @registry.histogram(name, docstring: docstring, labels: labels, buckets: buckets)
          end
        end
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
