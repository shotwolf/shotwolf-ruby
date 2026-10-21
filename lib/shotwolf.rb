# frozen_string_literal: true

require_relative "shotwolf/version"
require_relative "shotwolf/errors"
require_relative "shotwolf/client"

# Official Ruby SDK for the ShotWolf API - https://shotwolf.com
module Shotwolf
  # Convenience: Shotwolf.new(...) == Shotwolf::Client.new(...)
  def self.new(...)
    Client.new(...)
  end
end
