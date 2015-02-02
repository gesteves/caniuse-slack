# encoding: utf-8
require "sinatra"
require "json"
require "httparty"
require "dotenv"
require "text"
require "redis"

configure do
  # Load .env vars
  Dotenv.load
  # Set up redis
  case settings.environment
  when :development
    uri = URI.parse(ENV["LOCAL_REDIS_URL"])
  when :production
    uri = URI.parse(ENV["REDISCLOUD_URL"])
  end
  $redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
  # Disable output buffering
  $stdout.sync = true
end

# Handles the POST request made by the Slack Outgoing webhook
# Params sent in the request:
# 
# token=abc123
# team_id=T0001
# channel_id=C123456
# channel_name=test
# timestamp=1355517523.000005
# user_id=U123456
# user_name=Steve
# text=caniuse fontface
# trigger_word=caniuse
# 
post "/" do
  begin
    if params[:token] != ENV["OUTGOING_WEBHOOK_TOKEN"]
      response = "Invalid token"
    else
      params[:text] = params[:text].sub(params[:trigger_word], "").strip.downcase
      response = process_request(params)
    end
  rescue => e
    puts "[ERROR] #{e}"
    response = ""
  end
  puts "[LOG] #{params}"
  status 200
  if response != ""
    body json_response_for_slack(response)
  else
    body response
  end
end

# Puts together the json payload that needs to be sent back to Slack
# 
def json_response_for_slack(reply)
  response = { text: reply, link_names: 1 }
  response[:username] = ENV["BOT_USERNAME"] unless ENV["BOT_USERNAME"].nil?
  response[:icon_emoji] = ENV["BOT_ICON"] unless ENV["BOT_ICON"].nil?
  response.to_json
end

# Processes the user's request, either listing all features,
# or finding the requested feature and sending the outgoing webhook
def process_request(params)
  if params[:text] == ""
    response = get_all_features
  else
    response, feature = get_feature(params[:text])
    send_incoming_webhook(params[:text], feature, params[:channel_id]) unless feature.nil?
  end
  response
end

# Gets the requested feature from redis.
# If not found, gets the full caniuse json file and tries to find and exact match.
# If no exact match found, does a "fuzzy" search using white algorithm.
# If no results found, says so.
# If one result found, returns it.
# If more than one result found, ask user to be more specific.
# 
def get_feature(key)
  caniuse_data = get_caniuse_data
  features = caniuse_data["data"]
  matched_feature = features.find{ |k, h| k == key || h["title"].downcase == key }
  if !matched_feature.nil?
    feature = features[matched_feature.first]
    response = ""
  else
    white = Text::WhiteSimilarity.new
    matched_features = features.select{ |k, h| white.similarity(key, k) > 0.5 || white.similarity(key, h["title"].downcase) > 0.5 }
    if matched_features.size == 0
      response = "Sorry, I couldn't find data for `#{key}`."
    elsif matched_features.size == 1
      matched_feature = matched_features.first
      feature = features[matched_feature.first]
      response = ""
    else
      response = "Sorry, I couldn't find data for `#{key}`. Did you mean one of these? #{matched_features.collect{ |f| "`#{f.first}`" }.join(", ")}"
    end
  end
  return response, feature
end

# Get raw caniuse data from redis.
# If it's not in redis, GET from Github and cache in redis for a day.
# 
def get_caniuse_data
  caniuse_data = $redis.get("caniuse")
  if caniuse_data.nil?
    uri = "https://raw.githubusercontent.com/Fyrd/caniuse/master/data.json"
    request = HTTParty.get(uri)
    caniuse_data = request.body
    $redis.setex("caniuse", 60*60*24, caniuse_data)
  end
  JSON.parse(caniuse_data)
end

# Get a list of all available features
# 
def get_all_features
  features = $redis.get("caniuse:data:all")
  if features.nil?
    caniuse_data = get_caniuse_data
    features = "Available features: #{caniuse_data["data"].keys.sort.collect{ |f| "`#{f}`" }.join(", ")}"
    $redis.setex("caniuse:data:all", 60*60*24, features)
  end
  features
end

# Given the spec status code, gets the full name from the caniuse JSON.
# 
def get_status_name(code)
  status_name = $redis.get("caniuse:statuses:#{code}")
  if status_name.nil?
    caniuse_data = get_caniuse_data
    status_name = caniuse_data["statuses"][code]
    $redis.setex("caniuse:statuses:#{code}", 60*60*24, status_name)
  end
  status_name
end

# Given the browser key, gets the full browser name from the caniuse JSON
# 
def get_browser_name(code)
  browser_name = $redis.get("caniuse:agents:#{code}:browser")
  if browser_name.nil?
    caniuse_data = get_caniuse_data
    browser_name = caniuse_data["agents"][code]["browser"]
    $redis.setex("caniuse:agents:#{code}:browser", 60*60*24, browser_name)
  end
  browser_name
end

# Put together a JSON payload to send back to Slack, with
# the caniuse info as an attachment.
# See https://api.slack.com/docs/attachments for more info.
# 
def send_incoming_webhook(key, feature, channel_id)
  payload = $redis.get("payload:#{key}")
  if payload.nil?
    payload = {
      :text => ""
    }
    attachments = []
    attachments << build_attachment(key, feature)
    payload[:attachments] = attachments
    $redis.setex("payload:#{key}", 60*60*24, payload.to_json)
  else
    payload = JSON.parse(payload)
  end
  payload[:channel] = channel_id
  HTTParty.post(ENV["INCOMING_WEBHOOK_URL"], :body => payload.to_json)
end

# Builds the attachment to send with the payload back to slack.
# 
def build_attachment(key, feature)
  attachment = {}
  attachment[:color] = get_attachment_color(feature)
  attachment[:title] = feature["title"]
  attachment[:title_link] = "http://caniuse.com/#feat=#{key}"
  attachment[:text] = feature["description"]
  attachment[:fallback] = "#{feature["title"]} (http://caniuse.com/#feat=#{key}): #{feature["description"]}"
  attachment[:mrkdwn_in] = ["text", "title", "fields", "fallback"]
  fields = []
  fields << build_browser_support_field(feature)
  fields << build_support_field(feature)
  fields << build_spec_field(feature)
  fields << build_resources_field(feature)
  attachment[:fields] = fields
  attachment
end

# Sets the attachment border color depending on what the global browser
# support for the feature is.
# 
def get_attachment_color(feature)
  full_support = feature["usage_perc_y"].to_f
  if full_support > 90
    "good"
  elsif full_support > 50
    "warning"
  else
    "danger"
  end
end

# Builds the field the browser support percentage for the feature.
# 
def build_support_field(feature)
  {
    :title => "Total support worldwide",
    :value => "#{feature["usage_perc_y"]}%"
  }
end

# Builds the field linking the feature status and spec.
# 
def build_spec_field(feature)
  unless feature["spec"].nil? || feature["status"].nil?
    {
      :title => "Spec",
      :value => "<#{feature["spec"]}|#{get_status_name(feature["status"])}>"
    }
  end
end

# Builds a list of links and resources for the requested feature.
# 
def build_resources_field(feature)
  unless feature["links"].nil?
    resources = []
    feature["links"].each do |l|
      resources << "<#{l["url"]}|#{l["title"]}>"
    end
    {
      :title => "Links & resources",
      :value => resources.join("\n")
    }
  end
end

# Builds a list of browser versions that fully support the requested feature.
# 
def build_browser_support_field(feature)
  supported = []
  feature["stats"].each do |browser|
    name = get_browser_name(browser.first)
    versions = browser.last.select{ |k, v| v.match("y") }.first
    unless versions.nil?
      versions = "#{versions.first.split("-").first}"
      supported << "#{name} #{versions}"
    end
  end
  {
    :title => "Browsers with full support (prefixed & unprefixed)",
    :value => supported.sort_by!{ |browser| browser.downcase }.join("\n")
  }
end