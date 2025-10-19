# frozen_string_literal: true
require "openssl"
require "base64"

RsaKeys = Struct.new(:public_key, :private_key, keyword_init: true)

class RsaService
  KEY_SIZE = 2048
  PADDING  = OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING

  def generate_crypto_keys
    rsa = OpenSSL::PKey::RSA.new(KEY_SIZE)
    RsaKeys.new(public_key: rsa.public_key.to_pem, private_key: rsa.to_pem)
  end

  def encrypt(public_key_pem, plain_text)
    rsa = OpenSSL::PKey::RSA.new(public_key_pem)
    Base64.strict_encode64(rsa.public_encrypt(plain_text, PADDING))
  end

  def decrypt(private_key_pem, cipher_text_b64)
    rsa = OpenSSL::PKey::RSA.new(private_key_pem)
    rsa.private_decrypt(Base64.strict_decode64(cipher_text_b64), PADDING)
  end
end
