# frozen_string_literal: true
require "openssl"
require "base64"

AesKey = Struct.new(:key, :iv, keyword_init: true)

class AesService
  CIPHER = "aes-256-cbc"

  def generate_secret_key
    cipher = OpenSSL::Cipher.new(CIPHER)
    cipher.encrypt
    AesKey.new(
      key: Base64.strict_encode64(cipher.random_key),
      iv:  Base64.strict_encode64(cipher.random_iv)
    )
  end

  def encrypt(aes_key, plain_text)
    cipher = OpenSSL::Cipher.new(CIPHER)
    cipher.encrypt
    cipher.key = Base64.strict_decode64(aes_key.key)
    cipher.iv  = Base64.strict_decode64(aes_key.iv)
    Base64.strict_encode64(cipher.update(plain_text) + cipher.final)
  end

  def decrypt(aes_key, cipher_b64)
    cipher = OpenSSL::Cipher.new(CIPHER)
    cipher.decrypt
    cipher.key = Base64.strict_decode64(aes_key.key)
    cipher.iv  = Base64.strict_decode64(aes_key.iv)
    cipher.update(Base64.strict_decode64(cipher_b64)) + cipher.final
  end
end
