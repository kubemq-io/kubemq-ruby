# frozen_string_literal: true

RSpec.describe KubeMQ::ChannelInfo do
  describe '#initialize' do
    it 'stores all fields' do
      info = described_class.new(
        name: 'test-ch', type: 'events',
        last_activity: 100, is_active: true,
        incoming: 50, outgoing: 30
      )
      expect(info.name).to eq('test-ch')
      expect(info.type).to eq('events')
      expect(info.last_activity).to eq(100)
      expect(info.is_active).to be true
      expect(info.incoming).to eq(50)
      expect(info.outgoing).to eq(30)
    end

    it 'has sensible defaults' do
      info = described_class.new(name: 'ch', type: 'q')
      expect(info.last_activity).to eq(0)
      expect(info.is_active).to be false
      expect(info.incoming).to eq(0)
      expect(info.outgoing).to eq(0)
    end
  end

  describe '#active?' do
    it 'returns true when active' do
      info = described_class.new(name: 'ch', type: 't', is_active: true)
      expect(info).to be_active
    end

    it 'returns false when inactive' do
      info = described_class.new(name: 'ch', type: 't', is_active: false)
      expect(info).not_to be_active
    end
  end

  describe '.from_json' do
    it 'parses from string-keyed hash' do
      hash = {
        'name' => 'ch1', 'type' => 'events',
        'lastActivity' => 200, 'isActive' => true,
        'incoming' => 10, 'outgoing' => 5
      }
      info = described_class.from_json(hash)
      expect(info.name).to eq('ch1')
      expect(info.type).to eq('events')
      expect(info.last_activity).to eq(200)
      expect(info).to be_active
      expect(info.incoming).to eq(10)
      expect(info.outgoing).to eq(5)
    end

    it 'parses from symbol-keyed hash' do
      hash = { name: 'ch2', type: 'queues', last_activity: 50, is_active: false, incoming: 1, outgoing: 0 }
      info = described_class.from_json(hash)
      expect(info.name).to eq('ch2')
      expect(info.type).to eq('queues')
      expect(info.last_activity).to eq(50)
    end

    it 'handles missing keys with defaults' do
      hash = {}
      info = described_class.from_json(hash)
      expect(info.name).to eq('')
      expect(info.type).to eq('')
      expect(info.last_activity).to eq(0)
      expect(info.is_active).to be false
    end

    it 'prefers camelCase keys over snake_case' do
      hash = { 'lastActivity' => 100, 'last_activity' => 50 }
      info = described_class.from_json(hash)
      expect(info.last_activity).to eq(100)
    end
  end

  describe '#to_s' do
    it 'returns formatted string' do
      info = described_class.new(name: 'test', type: 'events', is_active: true)
      str = info.to_s
      expect(str).to include('test')
      expect(str).to include('events')
      expect(str).to include('true')
    end
  end
end
