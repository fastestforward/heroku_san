require 'heroku'
require 'heroku/api'
require 'json'

MOCK = false unless defined?(MOCK)

module HerokuSan
  class Stage
    attr_reader :name
    include Git
    
    def initialize(stage, options = {})
      @name = stage
      @options = options
    end
    
    def heroku
      @heroku ||= Heroku::API.new(:api_key => ENV['HEROKU_API_KEY'] || Heroku::Auth.api_key, :mock => MOCK)
    end

    def app
      @options['app'] or raise MissingApp, "#{name}: is missing the app: configuration value. I don't know what to access on Heroku."
    end
    
    def repo
      @options['repo'] ||= "git@heroku.com:#{app}.git"
    end
    
    def stack
      @options['stack'] ||= heroku.get_stack(app).body.detect{|stack| stack['current']}['name']
    end
    
    def tag
      @options['tag']
    end
    
    def config
      @options['config'] ||= {}
    end

    def addons
      (@options['addons'] ||= []).flatten
    end
    
    def run(command, args = nil)
      if stack =~ /cedar/
        sh_heroku "run #{command} #{args}"
      else
        sh_heroku "run:#{command} #{args}"
      end
    end
    
    def deploy(sha = nil, force = false)
      sha ||= git_parsed_tag(tag)
      git_push(sha, repo, force ? %w[--force] : [])
    end
    
    def migrate
      rake('db:migrate')
      restart
    end
    
    def rake(*args)
      run 'rake', args.join(' ')
      # heroku.rake app, args.join(' ')
    end

    def maintenance(action = nil)
      if block_given?
        heroku.post_app_maintenance(app, '1')
        begin
          yield
        ensure
          heroku.post_app_maintenance(app, '0')
        end
      else
        raise ArgumentError, "Action #{action.inspect} must be one of (:on, :off)", caller if ![:on, :off].include?(action)
        heroku.post_app_maintenance(app, {:on => '1', :off => '0'}[action])
      end
    end
    
    def create # DEPREC?
      params = Hash[@options.select{|k,v| %w[app stack].include? k}].stringify_keys
      params['name'] = params.delete('app')
      response = heroku.post_app(params)
      response.body['name']
    end

    def sharing_add(email) # DEPREC?
      sh_heroku "sharing:add #{email.chomp}"
    end
  
    def sharing_remove(email) # DEPREC?
      sh_heroku "sharing:remove #{email.chomp}"
    end
  
    def long_config
      heroku.get_config_vars(app).body
    end
    
    def push_config(options = nil)
      params = (options || config).stringify_keys
      heroku.put_config_vars(app, params).body
    end

    def get_installed_addons
      heroku.get_addons(app).body
    end

    def install_addons
      return if addons.empty?
      installed_addons = get_installed_addons
      addons_to_install = addons - installed_addons.map{|a|a['name']}
      if addons_to_install.any?
        (addons - installed_addons.map{|a|a['name']}).each do |addon|
          sh_heroku "addons:add #{addon}" rescue nil
        end
        installed_addons = get_installed_addons
      end
      installed_addons
    end

    def restart
      "restarted" if heroku.post_ps_restart(app).body == 'ok'
    end
  
    def logs(tail = false)
      sh_heroku 'logs' + (tail ? ' --tail' : '')
    end
    
    def revision
      git_named_rev(git_revision(repo))
    end
    
  private
  
    def sh_heroku(command)
      sh "heroku #{command} --app #{app}"
    end
  end
end

# from ActiveSupport
class Hash
  # Return a new hash with all keys converted to strings.
  def stringify_keys
    dup.stringify_keys!
  end

  # Destructively convert all keys to strings.
  def stringify_keys!
    keys.each do |key|
      self[key.to_s] = delete(key)
    end
    self
  end
end