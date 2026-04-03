# frozen_string_literal: true

RSpec.describe KubeMQ::Transport::MessageBuffer do
  subject(:buffer) { described_class.new(capacity: 3) }

  describe '#push' do
    it 'adds messages to the buffer' do
      buffer.push('msg1')
      expect(buffer.size).to eq(1)
    end

    it 'discards oldest when buffer overflows' do
      buffer.push('msg1')
      buffer.push('msg2')
      buffer.push('msg3')
      buffer.push('msg4')
      messages = buffer.drain
      expect(messages).to eq(%w[msg2 msg3 msg4])
    end
  end

  describe '#drain' do
    it 'returns all messages and empties the buffer' do
      buffer.push('a')
      buffer.push('b')
      messages = buffer.drain
      expect(messages).to eq(%w[a b])
      expect(buffer).to be_empty
    end

    it 'yields each message to block' do
      buffer.push('x')
      buffer.push('y')
      collected = []
      buffer.drain { |msg| collected << msg }
      expect(collected).to eq(%w[x y])
    end

    it 'returns empty array when buffer is empty' do
      expect(buffer.drain).to eq([])
    end
  end

  describe '#empty?' do
    it 'returns true initially' do
      expect(buffer).to be_empty
    end

    it 'returns false after push' do
      buffer.push('x')
      expect(buffer).not_to be_empty
    end
  end

  describe '#full?' do
    it 'returns true when at capacity' do
      3.times { |i| buffer.push("msg#{i}") }
      expect(buffer).to be_full
    end

    it 'returns false when below capacity' do
      buffer.push('msg1')
      expect(buffer).not_to be_full
    end
  end

  describe '#clear' do
    it 'removes all messages' do
      buffer.push('a')
      buffer.push('b')
      buffer.clear
      expect(buffer).to be_empty
    end
  end

  describe 'default capacity' do
    it 'uses 1000 as default' do
      buf = described_class.new
      expect(buf.capacity).to eq(1000)
    end
  end
end
