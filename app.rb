# app.rb
# frozen_string_literal: true

require "sinatra"
require "sinatra/json"
require "json"
require_relative "services/rsa_service"
require "base64"

set :bind, "0.0.0.0"
set :port, 5132
set :protection, except: [:json_csrf]
set :show_exceptions, false
set :server, :webrick

# раздача статичных (Swagger YAML)
set :static, false
set :public_folder, File.join(__dir__, "public")

# In-memory стор для сотрудников
STORE = {
  next_id: 1,
  employees: []
}

# In-memory стор для RSA ключей
RSA_STORE = {
  next_id: 1,
  items: {}
}

helpers do
  def parse_json_body
    request.body.rewind
    raw = request.body.read
    return {} if raw.nil? || raw.strip.empty?
    JSON.parse(raw)
  rescue JSON::ParserError
    halt 400, json(error: "Invalid JSON")
  end

  def sanitize_name(str)
    (str || "").to_s.strip
  end

  def parse_int(value)
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def find_employee!(id)
    emp = STORE[:employees].find { |e| e[:id] == id }
    halt 404, json(error: "Employee not found") unless emp
    emp
  end

  def validate_employee_fields(first_name, last_name, age)
    errors = []
    errors << "firstName is required" if first_name.empty?
    errors << "lastName is required"  if last_name.empty?
    errors << "age must be a non-negative integer" if age.nil? || age.negative?
    errors
  end

  def duplicate?(first_name, last_name, age, except_id: nil)
    normalized = [first_name.downcase, last_name.downcase, age]
    STORE[:employees].any? do |e|
      next if except_id && e[:id] == except_id
      [e[:firstName].downcase, e[:lastName].downcase, e[:age]] == normalized
    end
  end
end

# CORS — применяется ко всем запросам
before do
  headers "Access-Control-Allow-Origin"  => "*",
          "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers" => "Content-Type, Authorization, Accept"
end

options "*" do
  200
end

# Swagger YAML
get "/swagger/openapi.yaml" do
  content_type "text/yaml"
  headers "Access-Control-Allow-Origin"  => "*",
          "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers" => "Content-Type, Authorization, Accept"
  send_file File.join(settings.public_folder, "swagger", "openapi.yaml")
end

# Employees CRUD

get "/employees" do
  json STORE[:employees]
end

get "/employees/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Employee not found") unless id
  emp = find_employee!(id)
  json emp
end

post "/employees" do
  payload    = parse_json_body
  first_name = sanitize_name(payload["firstName"])
  last_name  = sanitize_name(payload["lastName"])
  age        = parse_int(payload["age"])

  errors = validate_employee_fields(first_name, last_name, age)
  halt 400, json(error: errors.join(", ")) unless errors.empty?

  if duplicate?(first_name, last_name, age)
    halt 400, json(error: "Employee with same firstName, lastName and age already exists")
  end

  emp = {
    id: STORE[:next_id],
    firstName: first_name,
    lastName: last_name,
    age: age
  }
  STORE[:employees] << emp
  STORE[:next_id] += 1
  status 201
  json emp
end

put "/employees/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Employee not found") unless id
  emp = find_employee!(id)

  if request.media_type&.include?("application/json")
    payload    = parse_json_body
    first_name = sanitize_name(payload["firstName"] || emp[:firstName])
    last_name  = sanitize_name(payload["lastName"]  || emp[:lastName])
    age        = parse_int(payload.key?("age") ? payload["age"] : emp[:age])
  else
    first_name = sanitize_name(params["firstName"] || emp[:firstName])
    last_name  = sanitize_name(params["lastName"]  || emp[:lastName])
    age        = parse_int(params.key?("age") ? params["age"] : emp[:age])
  end

  errors = validate_employee_fields(first_name, last_name, age)
  halt 400, json(error: errors.join(", ")) unless errors.empty?

  if duplicate?(first_name, last_name, age, except_id: emp[:id])
    halt 400, json(error: "Another employee with same firstName, lastName and age exists")
  end

  emp[:firstName] = first_name
  emp[:lastName]  = last_name
  emp[:age]       = age

  json emp
end

delete "/employees/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Employee not found") unless id
  emp = find_employee!(id)
  STORE[:employees].delete(emp)
  status 200
  json message: "Deleted"
end

#  RSA API

# POST -> сгенерировать пару, вернуть id
post "/api/crypto-keys/generate/rsa-keys" do
  keys = RsaService.new.generate_crypto_keys
  id = RSA_STORE[:next_id]
  RSA_STORE[:items][id] = keys
  RSA_STORE[:next_id] += 1
  status 201
  json id: id
rescue => e
  halt 400, json(error: e.message)
end

# GET вернуть публичный ключ в base64 по id
get "/api/crypto-keys/rsa-public-key/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Key pair not found") unless id && RSA_STORE[:items].key?(id)
  pub_pem = RSA_STORE[:items][id].public_key
  content_type "text/plain"
  Base64.strict_encode64(pub_pem)
end

# Домашняя
get "/" do
  <<~HTML
    <h1>TestServer.Api</h1>
    <p>CRUD: /employees</p>
    <p>RSA: POST /api/crypto-keys/generate/rsa-keys → {"id":N}</p>
    <p>RSA: GET /api/crypto-keys/rsa-public-key/{id} → base64(public key PEM)</p>
    <p>OpenAPI: <a href="/swagger/openapi.yaml">/swagger/openapi.yaml</a></p>
  HTML
end

# Глобальный обработчик ошибок
error do
  e = env["sinatra.error"]
  status 500
  json error: e.message
end
