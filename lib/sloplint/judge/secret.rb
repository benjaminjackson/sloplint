# frozen_string_literal: true

require "open3"

module Sloplint
  module Judge
    # Where the API key comes from: the environment first, then the OS store,
    # which is the login keychain through /usr/bin/security on macOS and
    # libsecret through secret-tool on Linux. Ruby never handles the value on
    # the way in: `key set` execs the platform tool and the tool prompts for
    # it. See docs/JUDGE.md "Where the key lives".
    module Secret
      SERVICE = "sloplint-judge"
      SECURITY = "/usr/bin/security"
      # Fixed locations, not PATH: a shadowing binary in a repository's
      # node_modules/.bin would otherwise be handed the real key at `key set`.
      SECRET_TOOL = %w[/usr/bin/secret-tool /usr/local/bin/secret-tool].freeze
      # A keychain item whose access list does not trust `security` makes
      # macOS open an Allow/Deny dialog and block; under an agent nobody sees
      # it, so a read gets this long and no longer.
      TIMEOUT = 15
      MISSING = "TYPESAFE_API_KEY is not set and no #{SERVICE} item is in the keychain; run `sloplint-judge key set`"

      module_function

      # [value, source] or nil; source is "environment" or "keychain".
      def fetch(name)
        env = ENV[name].to_s
        value, source = env.empty? ? [read(name), "keychain"] : [env, "environment"]
        return nil if value.nil? || value.empty?
        # Net::HTTP refuses a header with CR or LF by raising an ArgumentError
        # that quotes the whole header value, and the CLIs print ArgumentError
        # messages. Refuse here, without the value, so a wrapped paste stored
        # once is never printed on every run after.
        raise ArgumentError, "#{name} contains a control character; store it again" if value.match?(/[[:cntrl:]]/)

        [value, source]
      end

      # "environment", "keychain" or nil, without reading the value. The check
      # skill's probe runs this in every conversation, before anyone has
      # agreed to send anything, so it must not pull the secret into a process.
      def present?(name)
        return "environment" unless ENV[name].to_s.empty?

        found = case platform
                when :darwin then !run(SECURITY, "find-generic-password", "-s", SERVICE, "-a", name).nil?
                when :linux then (tool = secret_tool) && !run(tool, "search", "service", SERVICE, "account", name).to_s.empty?
                end
        found ? "keychain" : nil
      end

      # The stored value, or nil when there is no store, no tool or no item.
      def read(name)
        out = case platform
              when :darwin then run(SECURITY, "find-generic-password", "-s", SERVICE, "-a", name, "-w")
              when :linux then (tool = secret_tool) && run(tool, "lookup", "service", SERVICE, "account", name)
              end
        out&.chomp
      end

      # The argv `key set` execs with the terminal attached. `-w` last with no
      # value is the form the security(1) man page recommends: the tool prompts
      # for the password itself, so the value is never in any argv or in Ruby.
      # secret-tool prompts on a tty and reads stdin otherwise.
      def store_command(name)
        case platform
        when :darwin then [SECURITY, "add-generic-password", "-U", "-s", SERVICE, "-a", name, "-w"]
        when :linux then (tool = secret_tool) && [tool, "store", "--label=#{SERVICE}", "service", SERVICE, "account", name]
        end
      end

      def platform
        case RUBY_PLATFORM
        when /darwin/ then :darwin
        when /linux/ then :linux
        end
      end

      def secret_tool = SECRET_TOOL.find { |path| File.executable?(path) }

      # stdout on exit 0; nil on a missing binary or a non-zero exit. A run
      # that outlives TIMEOUT is killed and raises, because "no item" would be
      # the wrong report for "a dialog is waiting".
      def run(*argv)
        Open3.popen2(*argv, err: File::NULL) do |stdin, stdout, waiter|
          stdin.close
          unless waiter.join(TIMEOUT)
            Process.kill("KILL", waiter.pid)
            raise ArgumentError, "keychain lookup gave no answer in #{TIMEOUT} s: a keychain dialog may be waiting, " \
                                 "or the item does not allow #{argv.first}; see docs/JUDGE.md"
          end
          out = stdout.read
          waiter.value.success? ? out : nil
        end
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
