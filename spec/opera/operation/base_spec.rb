# frozen_string_literal: true

require 'rails_helper'
require 'dry-types'

module ProFinda
  RSpec.describe Operation::Base, type: :operation do
    let(:operation_class) do
      Class.new(Operation::Base) do
        validate :validation_1
        step :step_1

        validate do
          step :validation_2
        end

        def step_1; end

        def validation_1
          Dry::Validation.Schema do
          end.call({})
        end

        def validation_2
          Dry::Validation.Schema do
          end.call({})
        end
      end
    end

    subject { operation_class.call }

    describe '.instructions' do
      it {
        expect(operation_class.instructions).to eq([
                                                     {
                                                       kind: :validate, method: :validation_1
                                                     },
                                                     {
                                                       kind: :step, method: :step_1
                                                     },
                                                     {
                                                       instructions: [
                                                         {
                                                           kind: :step, method: :validation_2
                                                         }
                                                       ],
                                                       kind: :validate
                                                     }
                                                   ])
      }
    end

    describe '.result' do
      it { expect(subject).to be_an_instance_of(ProFinda::Operation::Result) }
    end

    describe '.call' do
      let(:params) do
        {}
      end

      let(:dependencies) do
        {}
      end

      subject { operation_class.call(params: params, dependencies: dependencies) }

      context 'for validations' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            validate do
              step :validation_1
              step :validation_2
            end
            step :step_1

            def step_1; end

            def validation_1
              Dry::Validation.Schema do
                required(:profile_id).filled(:int?)
              end.call(params)
            end

            def validation_2
              Dry::Validation.Schema do
                required(:profile_id).filled(eql?: 102)
              end.call(params)
            end
          end
        end

        context 'when passing' do
          let(:params) do
            {
              profile_id: 102
            }
          end

          it 'calls validations' do
            expect(subject).to be_success
            expect(subject.errors).to be_empty
          end

          it 'calls steps' do
            expect_any_instance_of(operation_class).to receive(:step_1)
            subject
          end
        end

        context 'when failing' do
          let(:params) do
            {
              profile_id: :example
            }
          end

          it 'calls validations' do
            expect(subject).to be_failure
            expect(subject.errors).to eq(profile_id: ['must be an integer', 'must be equal to 102'])
          end

          it 'calls call validations' do
            expect_any_instance_of(operation_class).to receive(:validation_2).and_call_original
            subject
          end

          it 'never calls step' do
            expect_any_instance_of(operation_class).to_not receive(:step_1)
            subject
          end
        end
      end

      context 'for steps' do
        context 'for failing step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              step :step_3
              step :step_4

              def step_1
                true
              end

              def step_2
                finish!
              end

              def step_3
                true
              end

              def step_4
                true
              end
            end
          end

          it 'calls step_1 only' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_3)

            expect(subject.executions).to match_array(%i[step_1 step_2])
            expect(subject).to be_success
          end

          context 'for multiple calls' do
            subject { operation_class }

            it 'is stateless' do
              expect_any_instance_of(operation_class).to_not receive(:step_3)

              5.times do
                expect(subject.call(params: params)).to be_success
                expect(subject.call(params: params).executions).to match_array(%i[step_1 step_2])
              end
            end
          end
        end

        context 'for erroring step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1
                result.add_error(:foo, 'bar')
              end

              def step_2
                result.add_errors(foo2: ['bar2'], foo: ['bar3'])
              end
            end
          end

          it 'finishes on first erroring step' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_2)
            expect(subject.executions).to match_array(%i[step_1])
            expect(subject).to be_failure
            expect(subject.errors).to eq(
              foo: %w[bar]
            )
          end
        end

        context 'for exceptioning step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1
                raise(StandardError, 'Example')
              end

              def step_2
                true
              end
            end
          end

          it 'calls step_1 only' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_2)
            expect(subject.executions).to match_array(%i[step_1])
            expect(subject).to be_failure
            expect(subject.exceptions).to eq('step_1' => ['Example'])
          end
        end
      end

      context 'for success' do
        context 'for failing step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              success do
                step :step_1
                step :step_2
                step :step_3
              end

              step :step_4

              def step_1
                true
              end

              def step_2
                false
              end

              def step_3
                true
              end

              def step_4
                true
              end
            end
          end

          it 'calls all the steps' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_3).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_4).and_call_original
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3 step_4])
            expect(subject).to be_success
          end
        end

        context 'for erroring step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              success do
                step :step_1
                step :step_2
              end

              step :step_3
              def step_1
                result.add_error(:foo, 'bar')
              end

              def step_2
                result.add_errors(foo2: ['bar2'], foo: ['bar3'])
              end

              def step_3
                true
              end
            end
          end

          it 'finishes on first erroring step' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_3)
            expect(subject.executions).to match_array(%i[step_1 step_2])
            expect(subject).to be_failure
            expect(subject.errors).to eq(
              foo: %w[bar bar3],
              foo2: %w[bar2]
            )
          end
        end

        context 'for exceptioning step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              def self.name
                'MyClass'
              end

              success do
                step :step_1
                step :step_2
              end

              def step_1
                raise(StandardError, 'Example')
              end

              def step_2
                true
              end
            end
          end

          it 'calls step_1 only' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect(subject.executions).to match_array(%i[step_1 step_2])
            expect(subject).to be_failure
            expect(subject.exceptions).to eq('MyClass#step_1' => ['Example'])
          end
        end
      end

      context 'for context' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1
              context[:foo] = :bar
            end

            def step_2
              result.output = "Context #{context[:foo]}"
            end
          end
        end

        it 'shares context between steps' do
          expect(subject.output).to eq('Context bar')
        end

        it 'DOES NOT have access to context from outside of operation' do
          expect(subject.methods).to_not include(:context)
        end
      end

      context 'for output' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1
              result.output = { model: { foo: :bar } }
            end

            def step_2
              new_output = result.output.merge(status: :ok)
              result.output = new_output
            end
          end
        end

        it 'returns correct output' do
          expect(subject.output).to eq(model: { foo: :bar }, status: :ok)
        end
      end

      context 'for configuration' do
        let(:transaction_class) do
          Class.new do
            def self.transaction
              yield
            end
          end
        end

        before do
          Operation::Config.configure do |config|
            config.transaction_class = transaction_class
          end
        end

        subject { operation_class }

        context 'when we use defaults' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1; end

              def step_2; end
            end
          end

          it 'uses global transaction' do
            expect(Operation::Config.transaction_class).to eq(transaction_class)
            expect(subject.config.transaction_class).to eq(transaction_class)
          end
        end

        context 'when we use specified configuration' do
          let(:new_transaction_class) do
            Class.new do
              def self.transaction
                yield
              end
            end
          end

          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1; end

              def step_2; end
            end
          end

          before do
            operation_class.configure do |config|
              config.transaction_class = new_transaction_class
            end
          end

          it 'uses specifed transaction' do
            expect(Operation::Config.transaction_class).to eq(transaction_class)
            expect(subject.config.transaction_class).to eq(new_transaction_class)
          end
        end
      end

      context 'for transaction' do
        let(:transaction_class) do
          Class.new do
            def self.transaction
              yield
            end
          end
        end

        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2
            transaction do
              step :step_3
              step :step_4
            end
            step :step_5

            def step_1
              true
            end

            def step_2
              true
            end

            def step_3
              true
            end

            def step_4
              1
            end

            def step_5
              true
            end
          end
        end

        before do
          Operation::Config.configure do |config|
            config.transaction_class = transaction_class
          end
        end

        it 'evaluates all steps' do
          expect(subject.executions).to match_array(%i[step_1 step_2 step_3 step_4 step_5])
        end

        context 'for raising exception' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              transaction do
                step :step_3
                step :step_4
              end
              step :step_5

              def step_1
                true
              end

              def step_2
                true
              end

              def step_3
                raise(StandardError, 'example')
              end

              def step_4
                true
              end

              def step_5
                true
              end
            end
          end

          it 'keeps track on exceptions' do
            expect(subject.exceptions).to include('step_3' => ['example'])
          end

          it 'evaluates 3 steps' do
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3])
          end

          it 'fails' do
            expect(subject).to be_failure
          end
        end

        context 'for finished execution step inside transaction' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              transaction do
                step :step_3
                step :step_4
              end
              step :step_5

              def step_1
                false
              end

              def step_2
                true
              end

              def step_3
                finish!
              end

              def step_4
                true
              end

              def step_5
                true
              end
            end
          end

          it 'evaluates 3 steps' do
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3])
          end

          it 'ends with success' do
            expect(subject).to be_success
          end
        end
      end

      context 'for operation' do
        let(:failing_operation) do
          Class.new(Operation::Base) do
            step :step_1

            def step_1
              result.add_error(:base, 'Inner error')
            end
          end
        end

        let(:valid_operation) do
          Class.new(Operation::Base) do
            step :step_44

            def step_44
              result.output = { example: 'output' }
            end
          end
        end

        let(:operation_class) do
          Class.new(Operation::Base) do
            operation :operation_1
            step :step_1

            def operation_1
              dependencies[:injected_operation].call
            end

            def step_1
              result.output = context[:operation_1_output]
            end
          end
        end

        context 'when the inner operation fails' do
          let(:dependencies) do
            { injected_operation: failing_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_failure
          end

          it 'adds inner errors into the result' do
            expect(subject.errors).to have_key(:base)
          end
        end

        context 'when the inner operation is valid' do
          let(:dependencies) do
            { injected_operation: valid_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_success
          end

          it 'adds contains the inner executions in the executions array' do
            expect(subject.executions).to eq([{ operation_1: [:step_44] }, :step_1])
          end

          it 'adds the output to the context of the operation' do
            expect(subject.output).to have_key(:example)
          end
        end
      end

      context 'for operations' do
        let(:failing_operation) do
          Class.new(Operation::Base) do
            step :step_1

            def step_1
              result.add_error(:base, 'Inner error')
            end
          end
        end

        let(:valid_operation) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1; end

            def step_2
              result.output = { example: 'output' }
            end
          end
        end

        let(:operation_class) do
          Class.new(Operation::Base) do
            operations :operations_collection
            step :step_1

            def operations_collection
              (1..3).map do
                dependencies[:injected_operation].call
              end
            end

            def step_1
              result.output = context[:operations_collection_output]
            end
          end
        end

        context 'when the inner operation fails' do
          let(:dependencies) do
            { injected_operation: failing_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_failure
          end

          it 'adds inner errors into the result' do
            expect(subject.errors).to have_key(:base)
          end
        end

        context 'when the operations step throws exception' do
          let(:dependencies) do
            { injected_operation: valid_operation }
          end

          let(:operation_class) do
            Class.new(Operation::Base) do
              operations :operations_collection
              step :step_1

              def operations_collection
                nil.unknown_method?
                (1..3).map do
                  dependencies[:injected_operation].call
                end
              end

              def step_1
                result.output = context[:operations_collection_output]
              end
            end
          end

          it 'ends with failure' do
            expect(subject).to be_failure
          end

          it 'gives additional information about' do
            expect(subject.exceptions['operations_collection']).to include(match('undefined method'))
            expect(subject.executions).to match_array([:operations_collection])
          end
        end

        context 'when the inner operation is valid' do
          let(:dependencies) do
            { injected_operation: valid_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_success
          end

          it 'adds contains the inner executions in the executions array' do
            expect(subject.executions).to eq([{
                                               operations_collection: [%i[step_1 step_2],
                                                                       %i[step_1 step_2],
                                                                       %i[step_1 step_2]]
                                             }, :step_1])
          end

          it 'adds the output to the context of the operations' do
            expect(subject.output.size).to eq(3)
            subject.output.each do |output|
              expect(output).to eq(example: 'output')
            end
          end
        end
      end

      context 'for benchmark' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2
            benchmark do
              step :step_3
              step :step_4
            end
            step :step_5

            def step_1
              false
            end

            def step_2
              true
            end

            def step_3
              true
            end

            def step_4
              1
            end

            def step_5
              true
            end
          end
        end

        it 'ends with success' do
          expect(subject).to be_success
        end

        it 'add benchmark info to result' do
          expect(subject.information).to have_key(:real)
          expect(subject.information).to have_key(:total)
        end

        context 'for failing step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              benchmark do
                step :step_3
                step :step_4
              end
              step :step_5

              def step_1
                false
              end

              def step_2
                false
              end

              def step_3
                finish!
              end

              def step_4
                1
              end

              def step_5
                true
              end
            end
          end

          it 'executes only first 3 instructions' do
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3])
          end
        end
      end
    end
  end
end