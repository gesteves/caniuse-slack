# encoding: utf-8
require "sinatra"
require "json"
require "httparty"
require "dotenv"
require "text"

configure do
  # Load .env vars
  Dotenv.load
  # Disable output buffering
  $stdout.sync = true
end