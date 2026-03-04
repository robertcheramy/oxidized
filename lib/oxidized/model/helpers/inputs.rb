module Oxidized
  class Model
    module Inputs
      # Define multiple inputs as a sequence of equivalent options
      # Example: use ssh or telnet, then scp or ftp:
      # [:ssh, [:scp, :ftp]]
      def inputs(list = nil)
        return @inputs if list.nil?

        validate_inputs(list)
        @inputs = list
      end

      # Returns the input sequence for the model as an array of arrays of input
      # classes, filtered and ordered according to the provided +input_classes+
      # (as specified in the oxidized configuration file).
      # Raises OxidizedError if a required input was not activated in the
      # oxidized configuration file.
      def input_sequence(input_classes)
        model_inputs = inputs || [
          @cfg.filter_map do |input, block_list|
            input.to_sym unless block_list.empty?
          end
        ]

        model_inputs.map do |sequence|
          sequence = [sequence] unless sequence.is_a? Array
          selected = input_classes.select { |input| sequence.include?(input.to_sym) }
          logger.error "Needs one of #{sequence.inspect} to be configured" if selected.empty?

          selected
        end
      end

      private

      def validate_inputs(list)
        message = "inputs must be an array containing symbols or " \
                  "arrays of symbols"

        raise ArgumentError, message unless list.is_a? Array
        raise ArgumentError, message if list.empty?

        list.each do |group|
          case group
          when Symbol
            # Everything is fine
          when Array
            raise ArgumentError, message if group.empty?

            group.each do |input|
              raise ArgumentError, message unless input.is_a? Symbol
            end
          else
            raise ArgumentError, message
          end
        end
      end
    end
  end
end
