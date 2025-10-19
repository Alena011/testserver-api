1# frozen_string_literal: true
require "rspec"
require_relative "../services/aes_service"

RSpec.describe AesService do
  let(:service) { AesService.new }

  it "generates key+iv and encrypts/decrypts correctly" do
    key = service.generate_secret_key
    data = "Hello AES!"

    cipher = service.encrypt(key, data)
    plain  = service.decrypt(key, cipher)

    expect(plain).to eq(data)
    expect(key.key).to be_a(String)
    expect(key.iv).to be_a(String)
  end
end
