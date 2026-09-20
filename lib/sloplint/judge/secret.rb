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

      module_function

      def missing(name) = "#{name} is not set and no #{SERVICE} item for it is in the keychain; run `sloplint-judge key set`"

      # [value, source] or nil; source is "environment" or "keychain".
      def fetch(name)
        env = ENV[name].to_s
        value, source = env.empty? ? [read(name), "keychain"] : [env, "environment"]
        return nil if value.nil? || value.empty?

        refuse_control!(name, value)
        [value, source]
      end

      # "environment", "keychain" or nil, without reading the value. The check
      # skill's probe runs this in every conversation, before anyone has
      # agreed to send anything, so it must not pull the secret into a process.
      def present?(name)
        env = ENV[name].to_s
        unless env.empty?
          refuse_control!(name, env)
          return "environment"
        end

        stored?(name) ? "keychain" : nil
      end

      # Net::HTTP refuses a header with CR or LF by raising an ArgumentError
      # that quotes the whole header value, and the CLIs print ArgumentError
      # messages. Refuse here, without the value, so a wrapped paste stored
      # once is never printed on every run after. `status` applies it too:
      # a key `check --judge` would refuse is not a key that is set up.
      def refuse_control!(name, value)
        raise ArgumentError, "#{name} contains a control character; store it again" if value.match?(/[[:cntrl:]]/)
      end

      # Is there a keychain item, whatever the environment says. On macOS an
      # attribute lookup does not open the access dialog and does not return
      # the value. On Linux there is no attribute-only lookup: secret-tool
      # prints the secret, so this reads the exit status and throws the
      # child's stdout away.
      def stored?(name)
        case platform
        when :darwin then !run(SECURITY, "find-generic-password", "-s", SERVICE, "-a", name).nil?
        when :linux then !!(tool = secret_tool) && ran?(tool, "lookup", "service", SERVICE, "account", name)
        else false
        end
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

      # The argv `key unset` runs. No prompt, no value, so no terminal needed.
      def delete_command(name)
        case platform
        when :darwin then [SECURITY, "delete-generic-password", "-s", SERVICE, "-a", name]
        when :linux then (tool = secret_tool) && [tool, "clear", "service", SERVICE, "account", name]
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
          # Drain the pipe while the child runs. A child that writes more
          # than the pipe holds blocks on the write until someone reads, and
          # waiting first would call that a keychain dialog and kill it.
          reader = Thread.new { Thread.current.report_on_exception = false; stdout.read }
          wait!(waiter, argv)
          out = reader.value
          waiter.value.success? ? out : nil
        end
      rescue Errno::ENOENT
        nil
      end

      # True when argv exits 0, with its stdout sent to /dev/null: this is how
      # a presence check runs a tool that would otherwise print the secret.
      def ran?(*argv)
        waiter = Process.detach(Process.spawn(*argv, in: File::NULL, out: File::NULL, err: File::NULL))
        wait!(waiter, argv)
        waiter.value.success?
      rescue Errno::ENOENT
        false
      end

      def wait!(waiter, argv)
        return if waiter.join(TIMEOUT)

        begin
          Process.kill("KILL", waiter.pid)
        rescue Errno::ESRCH
          # The child finished on its own between the join and the signal, so
          # there was nothing left to kill. What it answered is the honest
          # outcome, and a timeout it did not hit is not: wait for the thread
          # that reaped it and let the caller read the status.
          waiter.join
          return
        end
        # Reap the one that was killed here, rather than leaving a child
        # behind for the error below to unwind past.
        waiter.join(1)
        raise ArgumentError, "keychain lookup gave no answer in #{TIMEOUT} s: a keychain dialog may be waiting, " \
                             "or the item does not allow #{argv.first}; see docs/JUDGE.md"
      end
    end
  end
end
