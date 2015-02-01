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
    puts "[LOG] #{params}"
    if params[:token] != ENV["OUTGOING_WEBHOOK_TOKEN"]
      response = "Invalid token"
    else
      params[:text] = params[:text].sub(params[:trigger_word], "").strip.downcase
      response = find_feature(params)
    end
  rescue => e
    puts "[ERROR] #{e}"
    response = ""
  end
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

# Get the caniuse data json, then do some fuzzy matching to find the requested feature.
# If the feature key or title is matched exactly, send an empty response back to the outgoing webhook
# and use the incoming webhook to send a properly formatted attachment.
# If the received keyword doesn't match exactly, use the white similarity algorithm to find some
# candidates to suggest back to the user.
# 
def find_feature(params)
  caniuse_data = get_caniuse_data
  features = caniuse_data["data"]
  matched_feature = features.find{ |key, hash| key == params[:text] || hash["title"].downcase == params[:text] }
  if !matched_feature.nil?
    send_incoming_webhook(matched_feature.first, features[matched_feature.first], params[:channel_id])
    response = ""
  else
    white = Text::WhiteSimilarity.new
    matched_features = features.select{ |key, hash| white.similarity(params[:text], key) > 0.5 || white.similarity(params[:text], hash["title"].downcase) > 0.5 }
    if matched_features.size == 0
      response = "Sorry, I couldn't find caniuse data for `#{params[:text]}`."
    elsif matched_features.size == 1
      matched_feature = matched_features.first
      send_incoming_webhook(matched_feature.first, features[matched_feature.first], params[:channel_id])
      response = ""
    else
      response = "Sorry, I couldn't find caniuse data for `#{params[:text]}`. Did you mean one of these? #{matched_features.collect{ |f| "`#{f.first}`" }.join(", ")}"
    end
  end
  response
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

# Put together a JSON payload to send back to Slack, with
# the caniuse info as an attachment.
# See https://api.slack.com/docs/attachments for more info.
# 
def send_incoming_webhook(key, feature, channel_id)
  payload = {
    :text => "",
    :channel => channel_id
  }
  attachments = []
  attachments << build_attachment(key, feature)
  payload[:attachments] = attachments 
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

# Given the spec status code, gets the full name from the caniuse JSON.
# 
def get_status_name(code)
  caniuse_data = get_caniuse_data
  caniuse_data["statuses"][code]
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

# Given the browser key, gets the full browser name from the caniuse JSON
# 
def get_browser_name(code)
  caniuse_data = get_caniuse_data
  caniuse_data["agents"][code]["browser"]
end