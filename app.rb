# app.rb
# frozen_string_literal: true

require "sinatra"
require "sinatra/json"
require "json"

set :bind, "0.0.0.0"
set :port, 5132
set :protection, except: [:json_csrf]
set :show_exceptions, false
#set :static, true # раздаём public/
set :static, false
set :public_folder, File.join(__dir__, "public")

STORE = {
  next_id: 1,
  employees: [] # {id:, firstName:, lastName:, age:}
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
  headers 'Access-Control-Allow-Origin'  => '*',
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type, Authorization, Accept'
end

options '*' do
  200
end

# Явный роут для YAML (с теми же заголовками)
get '/swagger/openapi.yaml' do
  content_type 'text/yaml'
  headers 'Access-Control-Allow-Origin'  => '*',
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type, Authorization, Accept'
  send_file File.join(settings.public_folder, 'swagger', 'openapi.yaml')
end


# GET /employees — вернуть всех
get "/employees" do
  json STORE[:employees]
end

# GET /employees/:id — вернуть по id или 404
get "/employees/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Employee not found") unless id
  emp = find_employee!(id)
  json emp
end

# POST /employees — создать, Content-Type: application/json
# Тело: { "firstName": "...", "lastName": "...", "age": 0 }
post "/employees" do
  payload = parse_json_body
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

# PUT /employees/:id — обновить
# По ТЗ: application/x-www-form-urlencoded.
put "/employees/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Employee not found") unless id
  emp = find_employee!(id)

  if request.media_type&.include?("application/json")
    payload = parse_json_body
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

# DELETE /employees/:id — удалить, 200 или 404
delete "/employees/:id" do
  id = parse_int(params[:id])
  halt 404, json(error: "Employee not found") unless id
  emp = find_employee!(id)
  STORE[:employees].delete(emp)
  status 200
  json message: "Deleted"
end

#  Простая страничка с ссылкой на Swagger
get "/" do
  <<~HTML
    <h1>TestServer.Api</h1>
    <p>CRUD: /employees</p>
    <p>OpenAPI: <a href="/swagger/openapi.yaml">/swagger/openapi.yaml</a></p>
  HTML
end

# Глобальный обработчик ошибок (красиво отдаём JSON)
error do
  e = env["sinatra.error"]
  status 500
  json error: e.message
end

