require 'strscan'
require_relative 'outputs'
require_relative 'helpers/inputs'

module Oxidized
  class Model
    include SemanticLogger::Loggable

    using Refinements

    include Oxidized::Config::Vars
    extend Oxidized::Model::Inputs

    # rubocop:disable Style/FormatStringToken
    METADATA_DEFAULT = "%{comment}Fetched by Oxidized with model %{model} " \
                       "from host %{name} [%{ip}]\n".freeze
    # rubocop:enable Style/FormatStringToken

    class << self
      def inherited(klass)
        super
        if klass.superclass == Oxidized::Model
          klass.instance_variable_set('@cmd',     Hash.new { |h, k| h[k] = [] })
          klass.instance_variable_set('@cfg',     Hash.new { |h, k| h[k] = [] })
          klass.instance_variable_set('@procs',   Hash.new { |h, k| h[k] = [] })
          klass.instance_variable_set '@expect',  []
          klass.instance_variable_set '@comment', nil
          klass.instance_variable_set '@prompt',  nil
          klass.instance_variable_set '@metadata', {}
          klass.instance_variable_set '@inputs', nil

        else # we're subclassing some existing model, take its variables
          instance_variables.each do |var|
            iv = instance_variable_get(var)
            klass.instance_variable_set var, iv.dup
            @cmd[:cmd] = iv[:cmd].dup if var.to_s == "@cmd"
          end
        end
      end

      def comment(str = "# ")
        @comment = if block_given?
                     yield
                   elsif not @comment
                     str
                   else
                     @comment
                   end
      end

      def prompt(regex = nil)
        @prompt = regex || @prompt
      end

      def cfg(*methods, **args, &block)
        [methods].flatten.each do |method|
          process_args_block(@cfg[method.to_s], args, block)
        end
      end

      def cfgs
        @cfg
      end

      # Store a command to be run against the device
      # cmd_arg can be:
      #  - a string (the command to be run)
      #  - a symbol
      #    - :all    - run the block against each command output
      #    - :secret - run the block against each command output when
      #                vars :remove_secret is true
      #    - :significant_changes - use the block to remove unsignificant
      #                changes
      # Optional arguments (**args):
      # - clear: true - replace all the stored blocks for this command
      #                 (monkey patching)
      # - prepend: true - prepend the block to the stored blocks for this
      #                   command (monkey patching)
      # - if: lambda - run the command only if the lambda evals to true
      # - input: symbol or array of symbols: for the inputs this command is to
      #        run against (default - run every command)
      def cmd(cmd_arg = nil, **args, &block)
        if cmd_arg.instance_of?(Symbol)
          process_args_block(@cmd[cmd_arg], args, block)
        else
          if args.include?(:if) && !(args[:if].is_a?(Proc) && args[:if].lambda?)
            logger.error "cmd #{cmd_arg.dump}: if must be a lambda"
            return
          end

          if args.include?(:input)
            unless [Symbol, Array].include?(args[:input].class)
              logger.error "cmd #{cmd_arg.dump}: input must be a symbol or an array of symbols"
              return
            end
            # Always use an array
            args[:input] = Array(args[:input])
          end

          process_args_block(@cmd[:cmd], args,
                             { cmd: cmd_arg, args: args, block: block })
        end
        logger.debug "Added #{cmd_arg} to the commands list"
      end

      def metadata(position, value = nil, &block)
        return unless %i[top bottom].include? position

        if block_given?
          @metadata[position] = block
        else
          @metadata[position] = value
        end
      end

      def cmds
        @cmd
      end

      def expect(regex, **args, &block)
        process_args_block(@expect, args, [regex, block])
      end

      def expects
        @expect
      end

      def clean(what)
        case what
        when :escape_codes
          ansi_escape_regex = /
            \r?        # Optional carriage return at start
            \e         # ESC character - starts escape sequence
            (?:        # Non-capturing group for different sequence types:
              # Type 1: CSI (Control Sequence Introducer)
              \[       # Literal '[' - starts CSI sequence
              [0-?]*   # Parameter bytes: digits (0-9), semicolon, colon, etc.
              [ -\/]*  # Intermediate bytes: space through slash characters
              [@-~]    # Final byte: determines the actual command
            |          # OR
              # Type 2: Simple escape
              [=>]     # Single character commands after ESC
            )
            \r?        # Optional carriage return at end
          /x
          expect ansi_escape_regex do |data, re|
            data.gsub re, ''
          end
        end
      end

      # calls the block at the end of the model, prepending the output of the
      # block to the output string
      #
      # @yield expects block which should return [String]
      # @return [void]
      def pre(**args, &block)
        process_args_block(@procs[:pre], args, block)
      end

      # calls the block at the end of the model, adding the output of the block
      # to the output string
      #
      # @yield expects block which should return [String]
      # @return [void]
      def post(**args, &block)
        process_args_block(@procs[:post], args, block)
      end

      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @return [Hash] hash proc procs :pre+:post to be prepended/postfixed to output
      attr_reader :procs

      private

      def process_args_block(target, args, block)
        if args[:clear]
          if block.instance_of?(Array)
            target.reject! { |k, _| k == block[0] }
            target.push(block)
          elsif block.instance_of?(Hash)
            target.reject! { |item| item[:cmd] == block[:cmd] }
            target.push(block)
          else
            target.replace([block])
          end
        else
          method = args[:prepend] ? :unshift : :push
          target.send(method, block)
        end
      end
    end

    attr_accessor :input, :node

    # input specifies to run this command only with this input type
    # if input is not specified, always run the command
    def cmd(string, input: nil, &block)
      logger.debug "Executing #{string}"
      out = if input.nil? || input.include?(@input.to_sym)
              out = @input.cmd(string)
            else
              # Do not run this command
              return ""
            end
      return false unless out

      out = out.b unless Oxidized.config.input.utf8_encoded?
      self.class.cmds[:all].each do |all_block|
        out = instance_exec out, string, &all_block
      end
      if vars :remove_secret
        self.class.cmds[:secret].each do |all_block|
          out = instance_exec out, string, &all_block
        end
      end
      out = instance_exec out, &block if block
      process_cmd_output out, string
    end

    def metadata(position)
      return unless %i[top bottom].include? position

      model_metadata = self.class.instance_variable_get(:@metadata)
      var_position = { top: "metadata_top", bottom: "metadata_bottom" }
      if model_metadata[:top] || model_metadata[:bottom]
        # the model defines metadata at :top ot :bottom, use the model
        value = model_metadata[position]
        value.is_a?(Proc) ? instance_eval(&value) : interpolate_string(value)
      elsif vars("metadata_top") || vars("metadata_bottom")
        # vars defines metadata_top or metadata bottom, use the vars
        interpolate_string(vars(var_position[position]))
      elsif position == :top
        # default: use METADATA_DEFAULT for top
        interpolate_string(METADATA_DEFAULT)
      end
    end

    def interpolate_string(template)
      return nil unless template

      time = Time.now
      template_variables = {
        model:   self.class.name,
        name:    node.name,
        ip:      node.ip,
        group:   node.group,
        comment: self.class.comment,
        year:    time.year,
        month:   "%02d" % time.month,
        day:     "%02d" % time.day,
        hour:    "%02d" % time.hour,
        minute:  "%02d" % time.min,
        second:  "%02d" % time.sec
      }
      template % template_variables
    end

    def output
      @input.output
    end

    def send(data)
      @input.send data
    end

    def expect(...)
      self.class.expect(...)
    end

    def cfg
      self.class.cfgs
    end

    def prompt
      self.class.prompt
    end

    def expects(data)
      self.class.expects.each do |re, cb|
        if data.match re
          data = cb.arity == 2 ? instance_exec([data, re], &cb) : instance_exec(data, &cb)
        end
      end
      data
    end

    # Get the commands from the model
    def get
      logger.debug 'Collecting commands\' outputs'
      outputs = Outputs.new
      self.class.cmds[:cmd].each do |data|
        command = data[:cmd]
        args = data[:args]
        block = data[:block]

        next if args.include?(:if) && !instance_exec(&args[:if])

        out = cmd command, input: args[:input], &block
        return false unless out

        outputs << out
      end
      procs = self.class.procs
      procs[:pre].each do |pre_proc|
        outputs.unshift process_cmd_output(instance_eval(&pre_proc), '')
      end
      procs[:post].each do |post_proc|
        outputs << process_cmd_output(instance_eval(&post_proc), '')
      end
      if vars("metadata") == true
        metadata_top = metadata(:top)
        metadata_bottom = metadata(:bottom)
        outputs.unshift metadata_top if metadata_top
        outputs << metadata_bottom if metadata_bottom
      end
      outputs
    end

    def comment(str)
      data = String.new('')
      str.each_line do |line|
        data << self.class.comment << line
      end
      data
    end

    def xmlcomment(str)
      # XML Comments start with <!-- and end with -->
      #
      # Because it's illegal for the first or last characters of a comment
      # to be a -, i.e. <!--- or ---> are illegal, and also to improve
      # readability, we add extra spaces after and before the beginning
      # and end of comment markers.
      #
      # Also, XML Comments must not contain --. So we put a space between
      # any double hyphens, by replacing any - that is followed by another -
      # with '- '
      data = String.new('')
      str.each_line do |_line|
        data << '<!-- ' << str.gsub(/-(?=-)/, '- ').chomp << " -->\n"
      end
      data
    end

    def screenscrape
      @input.class.to_s.match(/Telnet/) || vars(:ssh_no_exec)
    end

    def significant_changes(config)
      self.class.cmds[:significant_changes].each do |block|
        config = instance_exec config, &block
      end
      config
    end

    private

    def process_cmd_output(output, name)
      output = String.new('') unless output.instance_of?(String)
      output.process_cmd(name)
      output
    end
  end
end
