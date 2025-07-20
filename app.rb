require 'bundler/setup'
Bundler.require
require 'dotenv/load'

use Rack::Cors do
  allow do
    origins 'https://sorenumstot.com', 'http://localhost:4567', 'http://192.168.0.13:4567'
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
  - Loves snowboarding and eating ramen - has been to 300+ ramen shops in Japan!
  - Enjoys photography
  - Developing an English ramen application for foreigners in Japan
  - Open to collaboration on Ruby on Rails or Python applications
  - Fluent in English and Japanese

  Soren's top ramen restaurants:
    - Moyeo Mensuke https://maps.app.goo.gl/y4ehYzdppvaESSem8
    - Ramen Hayato https://maps.app.goo.gl/Z5S59f3E12sTUb1F8
    - Ramen Tsuji https://maps.app.goo.gl/Gs5tSsT5MdMLx6iDA
    - Ramen FeeL https://maps.app.goo.gl/W8N8xdxkbsxenfku6
    - Buta no Hoshi https://maps.app.goo.gl/xAqgorZep2zq2Huj6
    - Ramen Break Beats https://maps.app.goo.gl/wTawhKpXkwWZJJxHA
    - Seikoudoku https://maps.app.goo.gl/u3EWiuJCAgi9QpAm7
    - Ramen Kai https://maps.app.goo.gl/Dyg52Zna53FAVTm59
    - 

  Professional

  1. Kengaku Cloud
    - Worked on Biz Creation's Kengaku Cloud application. This is an application that helps homebuilders
    and real estate companies with customer acquisition.
    - Implemented our event page's new user interface which is now used by a majority of our users
    - Help implement our new user interface for our management page
    - Worked with legacy code and help fix numerous bug issues
    - Worked with API integrations including Google Clanedar and Open AI
    - Experience working with MCPs for AI assisted development
    - Optimize SQL and active record queries while also fixing sql injection vulnerabilities
    - In charge of yearly Rails appliaction upgrades and checking for deprecated settings

  2. Appocloud
    - This application is a appointment matching application connected to a user's google calendar
    - Users can send possible appointment times to their clients and when the client accepts the acepted time
    is posted to the user's google calendar
    - Worked with Turbo for for a modern user interface
    - Implemented background jobs for API connections to google calendar and handling google calendar events

  Personal Projects

  1. Ramen Ranger - An app to help foreigners find the best bowls of ramen around Japan
    - Utilizes the google maps API to display the shops Soren has visited
    - Uses Hotwire, Turbo, and SQLite to get experience using the full modern Ruby on Rails stack
    - Uses AWS S3 for storage of images

  2. Ozei - Restaurant reservation app (Ruby on Rails, JavaScript, PostgreSQL)
    - Final bootcamp project, role: Project Manager
    - Connects groups with Tokyo restaurant reservations via Hot Pepper API

  3. Slack Clone - Real-time chat app (Ruby on Rails, ActionCable, AJAX)
    - Individual project with instant messaging using ActionCable

  4. Crypto Portfolio Calculator - React + Rails app
    - Live crypto tracking with Coinmarketcap API integration

  5. Pet Rental Platform - AirBnB clone for pet rentals
    - Backend developer role, Ruby on Rails

  6. Movie Watchlist - Full-stack Rails app
    - Personal movie tracking application

  7. Pong Game - Python game using Turtle graphics
    - Two-player simultaneous gameplay

  8. Snake Game - Python OOP game with high score tracking
    - Uses CSV file for persistent high scores

  9. Etch-a-Sketch - Vanilla JavaScript DOM manipulation
    - Interactive drawing with adjustable grid size

  Tech Skills: Ruby on Rails, JavaScript, PostgreSQL, API integration, Advanced Git, React, Python, HTML, CSS, Heroku deployment

  Contact: Available on GitHub and LinkedIn
  Location: Osaka, Japan (originally San Diego, CA)
HEREDOC

def call_gemini_api(message)
  api_key = ENV['GEMINI_API_KEY']

  unless api_key
    return "Configuration error. Please contact Soren directly!"
  end

  system_prompt = <<HEREDOC
You are Soren's portfolio assistant. Answer questions about Soren's background, projects, and skills based on the following information. Be conversational, friendly, and enthusiastic about his work, especially his ramen adventures! Keep responses concise but informative (under 150 words).

If asked about something not in the portfolio data, politely redirect to contacting Soren directly via his LinkedIn or GitHub.

Portfolio Information:
#{PORTFOLIO_DATA}
HEREDOC

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
      temperature: 0.4
    }
  }.to_json

  response = http.request(request)

  if response.code == '200'
    data = JSON.parse(response.body)
    data.dig('candidates', 0, 'content', 'parts', 0, 'text')
  else
    puts "Gemini API Error: #{response.code} - #{response.body}"
    "Sorry, I'm having trouble right now. Please try again later or contact Soren directly!"
  end
rescue => e
  puts "Error calling Gemini: #{e.message}"
  "Sorry, something went wrong. Please contact Soren directly!"
end

def rate_limit_check(ip)
  $request_counts[ip] ||= []
  $request_counts[ip] << Time.now

  $request_counts[ip].reject! { |time| time < Time.now - 3600 }

  $request_counts[ip].length <= 10
end

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

  unless rate_limit_check(request.ip)
    status 429
    return { error: "Too many requests. Please wait a bit!" }.to_json
  end

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

  if user_message.length > 500
    return { error: "Message too long. Please keep it under 500 characters." }.to_json
  end

  begin
    response = call_gemini_api(user_message)
    { response: response }.to_json
  rescue => e
    puts "Chat error: #{e.message}"
    status 500
    { error: "Something went wrong. Please try again!" }.to_json
  end
end

get '/health' do
  content_type :json
  {
    status: 'ok',
    timestamp: Time.now,
    rate_limits: $request_counts.transform_values(&:length)
  }.to_json
end
