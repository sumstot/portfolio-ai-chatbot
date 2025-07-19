require 'sinatra'
require 'net/http'
require 'uri'
require 'json'
require 'rack/cors'
require 'dotenv'

# Enable CORS for your Netlify site
use Rack::Cors do
  allow do
    origins 'https://sorenumstot.com', 'http://localhost:4567'
    resource '*',
      headers: :any,
      methods: [:get, :post, :options]
  end
end

$request_counts = {}


PORTFOLIO_DATA = <<HEREDOC
  About Soren:
  - Currently based in Osaka, originally from San Diego, California
  - Web developer specializing in Ruby on Rails monoliths using hotwire postgres, JavaScript, Python
  - Currently learning advanced Ruby on Rails and React
  - Loves snowboarding and eating ramen - has been to 200+ ramen shops in Japan!
  - Developing an English ramen application for foreigners in Japan
  - Open to collaboration on Ruby on Rails or Python applications

  Key Projects:
  1. Ozei - Restaurant reservation app (Ruby on Rails, JavaScript, PostgreSQL)
    - Final bootcamp project, role: Project Manager
    - Connects groups with Tokyo restaurant reservations via Hot Pepper API

  2. Slack Clone - Real-time chat app (Ruby on Rails, ActionCable, AJAX)
    - Individual project with instant messaging using ActionCable

  3. Crypto Portfolio Calculator - React + Rails app
    - Live crypto tracking with Coinmarketcap API integration

  4. Pet Rental Platform - AirBnB clone for pet rentals
    - Backend developer role, Ruby on Rails

  5. Movie Watchlist - Full-stack Rails app
    - Personal movie tracking application

  6. Pong Game - Python game using Turtle graphics
    - Two-player simultaneous gameplay

  7. Snake Game - Python OOP game with high score tracking
    - Uses CSV file for persistent high scores

  8. Etch-a-Sketch - Vanilla JavaScript DOM manipulation
    - Interactive drawing with adjustable grid size

  Tech Skills: Ruby on Rails, JavaScript, React, Python, HTML, CSS, PostgreSQL, API integration, Heroku deployment

  Contact: Available on GitHub and LinkedIn
  Location: Osaka, Japan (originally San Diego, CA)
HEREDOC

def call_gemini_api(message)
  api_key = ENV['GEMINI_API_KEY']

  unless api_key
    return "Configuration error. Please contact Soren directly!"
  end

  # Create the system prompt with your portfolio data
  system_prompt = %{
You are Soren's portfolio assistant. Answer questions about Soren's background, projects, and skills based on the following information. Be conversational, friendly, and enthusiastic about his work, especially his ramen adventures! Keep responses concise but informative (under 150 words).

If asked about something not in the portfolio data, politely redirect to contacting Soren directly via his LinkedIn or GitHub.

Portfolio Information:
#{PORTFOLIO_DATA}
}

  uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=#{api_key}")

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'

  request.body = {
    contents: [
      {
        parts: [
          { text: system_prompt },
          { text: "User question: #{message}" }
        ]
      }
    ],
    generationConfig: {
      maxOutputTokens: 200,
      temperature: 0.7
    }
  }.to_json

  response = http.request(request)

  if response.code == '200'
    data = JSON.parse(response.body)
    data.dig('candidates', 0, 'content', 'parts', 0, 'text')
  else
    puts "Gemini API Error: #{response.code} - #{response.body}" # For debugging
    "Sorry, I'm having trouble right now. Please try again later or contact Soren directly!"
  end
rescue => e
  puts "Error calling Gemini: #{e.message}" # For debugging
  "Sorry, something went wrong. Please contact Soren directly!"
end

def rate_limit_check(ip)
  $request_counts[ip] ||= []
  $request_counts[ip] << Time.now

  # Clean requests older than 1 hour
  $request_counts[ip].reject! { |time| time < Time.now - 3600 }

  # Allow 10 requests per hour per IP
  $request_counts[ip].length <= 10
end

# Routes
get '/' do
  content_type :json
  {
    message: "Soren's Portfolio Chatbot API",
    status: "running",
    endpoints: ["/chat (POST)", "/health (GET)"]
  }.to_json
end

post '/chat' do
  content_type :json

  # Rate limiting
  unless rate_limit_check(request.ip)
    status 429
    return { error: "Too many requests. Please wait a bit!" }.to_json
  end

  # Parse request
  begin
    request_body = JSON.parse(request.body.read)
  rescue JSON::ParserError
    status 400
    return { error: "Invalid JSON" }.to_json
  end

  user_message = request_body['message']&.strip

  if user_message.nil? || user_message.empty?
    status 400
    return { error: "Please provide a message" }.to_json
  end

  # Basic input validation
  if user_message.length > 500
    return { error: "Message too long. Please keep it under 500 characters." }.to_json
  end

  begin
    response = call_gemini_api(user_message)
    { response: response }.to_json
  rescue => e
    puts "Chat error: #{e.message}" # For debugging
    status 500
    { error: "Something went wrong. Please try again!" }.to_json
  end
end

# Health check endpoint
get '/health' do
  content_type :json
  {
    status: 'ok',
    timestamp: Time.now,
    rate_limits: $request_counts.transform_values(&:length)
  }.to_json
end
