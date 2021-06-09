require 'puppet'
require 'puppet/util'
require 'fileutils'
require 'net/http'
require 'net/https'
require 'uri'
require 'yaml'
require 'json'
require 'time'

# rubocop:disable Style/ClassAndModuleCamelCase
# splunk_hec.rb
module Puppet::Util::Splunk_hec
  def settings
    return @settings if @settings
    @settings_file = Puppet[:confdir] + '/splunk_hec.yaml'

    @settings = YAML.load_file(@settings_file)
  end

  def token(source_type)
    # we want users to be able to provide different tokens per sourcetype if they want
    token_name = "token_#{source_type}"
    token = settings[token_name] || settings['token'] || raise(Puppet::Error, 'Must provide token parameter to splunk class')
  end

  def use_ssl(source_type)
    uri = get_splunk_url(source_type)
    uri.scheme == 'https'
  end

  def ca_certificates(ca_file_path)
    return if File.zero?(ca_file_path)
    splitcert = ""
    cert_arr = []
    i = 0
    File.readlines(ca_file_path) do |line|
      splitcert += line
      if line =~ /-----END [^\-]+-----/
        cert_arr << splitcert
        splitcert = ""
      end
    end

    cert_arr.map do |c|
      OpenSSL::X509::Certificate.new(c.to_s)
    end
  end

  def get_ssl_context
    if settings['ssl_ca'] && !settings['ssl_ca'].empty?
      ca_file_path = File.join(Puppet[:confdir], 'splunk_hec', settings['ssl_ca'])
      raise Puppet::Error, "CA file #{ssl_ca} does not exist" unless File.exist? ca_file_path
      ca_cert_collection = ca_certificates(ca_file_path)
      Puppet::SSL::SSLProvider.new.create_root_context(cacerts: ca_cert_collection)
    end
  end

  def submit_request(body)
    source_type = source_type = body['sourcetype'].split(':')[1]
    splunk_uri = get_splunk_url(source_type)
    ssl_context = get_ssl_context

    headers = {
      'Authorization' => "Splunk #{token(source_type)}",
      'Content-Type'  => 'application/json',
    }

    Puppet.info "Will verify #{splunk_uri} SSL identity" unless ssl_context.nil?

    client = Puppet::HTTP::Client.new(ssl_context: ssl_context)
    client.post(splunk_uri, body.to_json, headers: headers)
  end

  def store_event(event)
    host = event['host']
    epoch = event['time'].to_f

    timestamp = Time.at(epoch).to_datetime

    filename = timestamp.strftime('%F-%H-%M-%S-%L') + '.json'

    dir = File.join(Puppet[:reportdir], host)

    unless Puppet::FileSystem.exist?(dir)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod_R(0o750, dir)
    end

    file = File.join(dir, filename)

    begin
      File.open(file, 'w') do |f|
        f.write(event.to_json)
      end
    rescue => detail
      Puppet.log_exception(detail, "Could not write report for #{host} at #{file}: #{detail}")
    end
  end

  private

  def get_splunk_url(source_type)
    url_name = "url_#{source_type}"
    uri = settings[url_name] || settings['url']
    raise(Puppet::Error, 'Must provide url parameter to splunk class') unless uri
    URI.parse(uri)
  end

  def pe_console
    settings['pe_console'] || Puppet[:certname]
  end

  def record_event
    result = if settings['record_event'] == 'true'
               true
             else
               false
             end
    result
  end

  # standard function to make sure we're using the same time format our sourcetypes are set to parse
  def sourcetypetime(timestamp)
    time = Time.parse(timestamp)
    '%10.3f' % time.to_f
  end
end
