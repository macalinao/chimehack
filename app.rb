require "dotenv"
Dotenv.load

require "sinatra"
require "google_directions"
require "twilio-ruby"
require "nokogiri"
require "sanitize"
require "googlestaticmap"

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
      make_sms(message)
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
      Your destination is on the left.
    }
  end

  def make_sms(message)
    client.messages.create(
      from: ENV["TWILIO_PHONE_NUMBER"],
      to: number,
      body: message
    )
  end

  def image_url
    map = GoogleStaticMap.new(zoom: 11)
    map.markers << MapMarker.new({
      color: "red",
      location: MapLocation.new(address: places.first)
    })
    map.markers << MapMarker.new({
      color: "blue",
      location: MapLocation.new(address: places.last)
    })
    image_url = map.url("http")
  end

  def make_map
    client.messages.create(
      from: ENV["TWILIO_PHONE_NUMBER"],
      to: number,
      body: "",
      media_url: image_url
    )

    puts formatted_directions

    msg_parts = []
    msg_lines = formatted_directions.split("\n")
    msg_lines.each_slice(7) do |slice|
      msg_parts << slice.join("\n")
    end

    msg_parts.each do |part|
      puts part
      client.messages.create(
        from: ENV["TWILIO_PHONE_NUMBER"],
        to: number,
        body: part
      )
    end
  end

end
