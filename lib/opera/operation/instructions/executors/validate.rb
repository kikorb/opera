# frozen_string_literal: true

module Opera
  module Operation
    module Instructions
      module Executors
        class Validate < Executor
          def break_condition
            operation.finished?
          end

          private

          def evaluate_instruction(instruction)
            instruction[:kind] = :step
            dry_result = super
            add_instruction_output(instruction, dry_result.output)
            result.add_errors(dry_result.errors) unless dry_result.success?
          end
        end
      end
    end
  end
end
