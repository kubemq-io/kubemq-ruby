# frozen_string_literal: true

RSpec.describe KubeMQ::Subscription do
  let(:cancellation_token) { KubeMQ::CancellationToken.new }
  let(:thread) { Thread.new { sleep(60) } }

  subject(:subscription) do
    described_class.new(thread: thread, cancellation_token: cancellation_token)
  end

  after do
    cancellation_token.cancel
    thread.kill
    thread.join(1)
  end

  describe '#active?' do
    it 'returns true when status is active and thread is alive' do
      expect(subscription).to be_active
    end

    it 'returns false after cancel' do
      subscription.cancel
      expect(subscription).not_to be_active
    end
  end

  describe '#wait' do
    it 'delegates to thread.join with timeout' do
      result = subscription.wait(0.01)
      expect(result).to be_nil
    end
  end

  describe '#mark_error' do
    it 'sets status to error and stores the error' do
      error = RuntimeError.new('boom')
      subscription.mark_error(error)
      expect(subscription.status).to eq(:error)
      expect(subscription.last_error).to eq(error)
    end
  end

  describe '#mark_closed' do
    it 'sets status to closed' do
      subscription.mark_closed
      expect(subscription.status).to eq(:closed)
    end
  end
end
