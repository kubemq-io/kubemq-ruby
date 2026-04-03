# frozen_string_literal: true

RSpec.describe KubeMQ::ServerInfo do
  describe '#initialize' do
    it 'stores all fields' do
      info = described_class.new(
        host: 'localhost', version: '2.5.0',
        server_start_time: 1000, server_up_time_seconds: 500
      )
      expect(info.host).to eq('localhost')
      expect(info.version).to eq('2.5.0')
      expect(info.server_start_time).to eq(1000)
      expect(info.server_up_time_seconds).to eq(500)
    end
  end

  describe '.from_proto' do
    it 'converts ping result to ServerInfo' do
      ping_result = double('PingResult',
                           Host: 'broker.local',
                           Version: '3.0.0',
                           ServerStartTime: 2000,
                           ServerUpTimeSeconds: 1200)
      info = described_class.from_proto(ping_result)
      expect(info.host).to eq('broker.local')
      expect(info.version).to eq('3.0.0')
      expect(info.server_start_time).to eq(2000)
      expect(info.server_up_time_seconds).to eq(1200)
    end
  end

  describe '#to_s' do
    it 'returns formatted string' do
      info = described_class.new(
        host: 'h1', version: 'v1',
        server_start_time: 0, server_up_time_seconds: 300
      )
      str = info.to_s
      expect(str).to include('h1')
      expect(str).to include('v1')
      expect(str).to include('300')
    end
  end
end
