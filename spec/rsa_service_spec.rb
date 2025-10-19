# frozen_string_literal: true
require "spec_helper"
require_relative "../services/rsa_service"

RSpec.describe RsaService do
  let(:service) { RsaService.new }

  it "generates key pair and encrypts/decrypts correctly" do
    keys = service.generate_crypto_keys
    data = "Hello RSA!"

    cipher = service.encrypt(keys.public_key, data)
    plain  = service.decrypt(keys.private_key, cipher)

    expect(plain).to eq(data)
    expect(keys.public_key).to include("BEGIN PUBLIC KEY")
    expect(keys.private_key).to include("BEGIN RSA PRIVATE KEY").or include("BEGIN PRIVATE KEY")
  end
end
