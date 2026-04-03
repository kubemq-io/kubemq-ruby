# frozen_string_literal: true

RSpec.describe KubeMQ::CancellationToken do
  subject(:token) { described_class.new }

  describe '#cancelled?' do
    it 'returns false initially' do
      expect(token).not_to be_cancelled
    end

    it 'returns true after cancel' do
      token.cancel
      expect(token).to be_cancelled
    end
  end

  describe '#wait' do
    it 'blocks until cancelled' do
      result = nil
      thread = Thread.new { result = token.wait }
      sleep(0.05)
      token.cancel
      thread.join(2)
      expect(result).to be true
    end

    it 'returns false on timeout when not cancelled' do
      result = token.wait(timeout: 0.05)
      expect(result).to be false
    end

    it 'returns true immediately if already cancelled' do
      token.cancel
      result = token.wait(timeout: 1)
      expect(result).to be true
    end

    it 'cancel is idempotent' do
      token.cancel
      token.cancel
      expect(token).to be_cancelled
    end
  end
end
