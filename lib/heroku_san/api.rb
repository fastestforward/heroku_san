module HerokuSan
  class API
    def initialize(options = {})
      @heroku_api = Heroku::API.new(options)
    end

    def method_missing(name, *args)
      response = nil
      Bundler.with_clean_env do
        response = @heroku_api.send(name, *args)
      end
      response
    rescue Heroku::API::Errors::ErrorWithResponse => error
      status = error.response.headers["Status"]
      msg = JSON.parse(error.response.body)['error'] rescue '???'
      error.set_backtrace([])
      $stderr.puts "\nHeroku API ERROR: #{status} (#{msg})\n\n"
      raise error
    end
  end
end
