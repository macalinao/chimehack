require 'dotenv'
Dotenv.load

require 'sinatra'
require 'google_directions'
require 'twilio-ruby'
require 'nokogiri'
require 'sanitize'
require 'googlestaticmap'

post '/callback' do
  body = params[:Body]
  to = params[:From]

  sender = TwilioSender.new(body, to)
  sender.make_map
end

post '/sms' do
  body = params[:body]
  to = params[:to]

  sender = TwilioSender.new(body, to)
  sender.make_map
end

class TwilioSender

  attr_accessor :client, :places, :number
  attr_reader :directions

  def initialize(body, number)
    @client = Twilio::REST::Client.new ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']
    @places = body.split('to')
    @number = number
    init_directions
  end

  def init_directions
    response = GoogleDirections.new(places.first, places.last)
    doc = Nokogiri::XML(response.xml)
    directions = ''
    doc.xpath('/DirectionsResponse/route/leg/step/html_instructions').each do |step|
      directions << Sanitize.fragment("#{step.content}\n")
    end
    @directions = directions
  end

  def formatted_directions
    %{
      Let's get you home safely.
      #{directions}
      Your destination is on the left.
    }
  end

  def make_sms
    client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: number,
      body: directions
    )
  end

  def image_url
    map = GoogleStaticMap.new(zoom: 13)
    map.markers << MapMarker.new({
      color: 'red',
      location: MapLocation.new(address: places.first)
    })
    map.markers << MapMarker.new({
      color: 'blue',
      location: MapLocation.new(address: places.last)
    })
    image_url = map.url('http')
  end

  def make_map
    client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: number,
      body: formatted_directions,
      media_url: image_url
    )
  end

end
