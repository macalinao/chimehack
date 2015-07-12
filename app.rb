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
  puts params.to_h

  sender = TwilioSender.new(body, to)
  sender.make_response
end

class TwilioSender

  attr_accessor :client, :body, :places, :number

  def initialize(body, number)
    @client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
    @body = body
    @number = number
  end

  def make_response
    if body.includes?('to')
      @places = body.split('to')
      make_map
    else
      message = %{
        Welcome to Walkable! To get safe directions, text "<starting point> to <end point>".
      }
      make_sms(message)
    end
  end

  def directions
    response = GoogleDirections.new(places.first, places.last)
    doc = Nokogiri::XML(response.xml)
    directions = ''
    doc.xpath('/DirectionsResponse/route/leg/step/html_instructions').each do |step|
      directions << Sanitize.fragment("#{step.content}\n")
    end
    return directions
  end

  def formatted_directions
    %{
      Let's get you home safely.
      #{directions}
      Your destination is on the left.
    }
  end

  def make_sms(message)
    client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: number,
      body: message
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
