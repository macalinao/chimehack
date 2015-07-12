require "dotenv"
Dotenv.load

require "sinatra"
require "google_directions"
require "twilio-ruby"
require "nokogiri"
require "sanitize"
require "googlestaticmap"
require "polylines"

db = {}

post "/callback" do
  body = params[:Body]
  to = params[:From]

  sender = TwilioSender.new(body, to)
  sender.make_response
end

class TwilioSender

  attr_accessor :client, :body, :places, :number

  def initialize(body, number)
    @client = Twilio::REST::Client.new(ENV["TWILIO_ACCOUNT_SID"], ENV["TWILIO_AUTH_TOKEN"])
    @body = body
    @number = number
  end

  def make_response
    if body.include?("to")
      @places = body.split("to")
      make_map
    elsif body.include?("l:")
      location = body.split(":")[-1]
      message = %{
        We've recorded your last location: #{location}.
      }
      db[number] = location

      make_map_for(number)
    elsif body.include?("r:")
      report = body.split(":")[-1]
      message = %{
        You reported: #{report}

        Thanks for contributing to crowdsourcing with Walkable! We'll make sure to keep others out of this area.
      }
      make_sms(message)
    else
      message = %{
        Welcome to Walkable! Let's get you home safely.

        To get safe directions, text "<starting point> to <end point>".

        To record your last location, text "l: <your last location>".
      }
      make_sms(message)
    end
  end

  def directions
    response = GoogleDirections.new(places.first, places.last)
    doc = Nokogiri::XML(response.xml)
    directions = []
    doc.xpath("/DirectionsResponse/route/leg/step/html_instructions").each do |step|
      directions << Sanitize.fragment("#{step.content}")
    end
    @polyline = doc.xpath("/DirectionsResponse/route/overview_polyline/points").first.content
    return directions
  end

  def directions_str
    directions.each_with_index.map do |el, i|
      "#{i + 1}. #{el}"
    end.join("\n")
  end

  def formatted_directions
    %{
      Let's get you home safely.
      #{directions_str}
    }
  end

  def make_sms(message)
    client.messages.create(
      from: ENV["TWILIO_PHONE_NUMBER"],
      to: number,
      body: message
    )
  end

  def map
    map = GoogleStaticMap.new(zoom: 14)
    map.markers << MapMarker.new({
      color: "red",
      location: MapLocation.new(address: places.first)
    })
    map.markers << MapMarker.new({
      color: "blue",
      location: MapLocation.new(address: places.last)
    })

    if db.has_key?(number)
      map.markers << MapMarker.new({
        color: "green",
        location: MapLocation.new(address: db[number])
      })
    end

    map.paths << make_polyline
    map
  end

  def image_url
    image_url = map.url("http")
  end

  def make_polyline
    poly = MapPolygon.new(color: "0xFF0000FF", fillcolor: "0x00FF0000")
    parsed_polyline = Polylines::Decoder.decode_polyline(@polyline)
    parsed_polyline.values_at(* parsed_polyline.each_index.select {|i| i % 2 == 0}).each do |point|
      poly.points << MapLocation.new(latitude: point[0], longitude: point[1])
    end
    poly.points << MapLocation.new(latitude: parsed_polyline.last[0], longitude: parsed_polyline.last[1])
    poly
  end

  def make_map
    msg_parts = []
    msg_lines = formatted_directions.split("\n")
    msg_lines.each_slice(7) do |slice|
      msg_parts << slice.join("\n")
    end

    client.messages.create(
      from: ENV["TWILIO_PHONE_NUMBER"],
      to: number,
      body: "",
      media_url: image_url
    )

    msg_parts.each do |part|
      puts part
      client.messages.create(
        from: ENV["TWILIO_PHONE_NUMBER"],
        to: number,
        body: part
      ) if part.length > 10
    end
  end

end
