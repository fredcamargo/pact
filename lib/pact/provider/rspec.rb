require 'open-uri'
require 'pact/consumer_contract'
require 'pact/provider/matchers'
require 'pact/provider/test_methods'
require 'pact/provider/configuration'

module Pact
  module Provider
    module RSpec

      module InstanceMethods
        def app
          Pact.configuration.provider.app
        end
      end

      module ClassMethods

        include ::RSpec::Core::DSL

        def honour_pactfile pactfile_uri, options = {}
          puts "Filtering specs by: #{options[:criteria]}" if options[:criteria]
          consumer_contract = Pact::ConsumerContract.from_json(read_pact_from(pactfile_uri, options))
          describe "A pact between #{consumer_contract.consumer.name} and #{consumer_contract.provider.name}" do
            describe "in #{pactfile_uri}" do
              honour_consumer_contract consumer_contract, options
            end
          end
        end

        def honour_consumer_contract consumer_contract, options = {}
          describe_consumer_contract consumer_contract, options.merge({:consumer => consumer_contract.consumer.name})
        end

        private

        def describe_consumer_contract consumer_contract, options
          consumer_interactions(consumer_contract, options).each do |interaction|
            describe_interaction_with_provider_state interaction, options
          end
        end

        def consumer_interactions(consumer_contract, options)
          if options[:criteria].nil?
            consumer_contract.interactions
          else
            consumer_contract.find_interactions options[:criteria]
          end
        end

        def describe_interaction_with_provider_state interaction, options
          if interaction.provider_state
            describe "Given #{interaction.provider_state}" do
              describe_interaction interaction, options
            end
          else
            describe_interaction interaction, options
          end
        end

        def describe_interaction interaction, options

          describe description_for(interaction), :pact => :verify do

            interaction_context = InteractionContext.new

            before do
              interaction_context.run_once :before do
                set_up_provider_state interaction.provider_state, options[:consumer]
                replay_interaction interaction
                interaction_context.last_response = last_response
              end
            end

            after do
              interaction_context.run_once :after do
                tear_down_provider_state interaction.provider_state, options[:consumer]
              end
            end

            describe_response interaction.response, interaction_context
          end

        end

        def describe_response expected_response, interaction_context

          describe "returns a response which" do

            let(:expected_response_status) { expected_response['status'] }
            let(:expected_response_body) { expected_response['body'] }
            let(:response) { interaction_context.last_response }
            let(:response_status) { response.status }
            let(:response_body) { parse_body_from_response(response) }

            if expected_response['status']
              it "has status code #{expected_response['status']}" do
                expect(response_status).to eql expected_response_status
              end
            end

            if expected_response['headers']
              describe "includes headers" do
                expected_response['headers'].each do |name, expected_header_value|
                  it "\"#{name}\" with value \"#{expected_header_value}\"" do
                    header_value = response.headers[name]
                    expect(header_value).to match_term expected_header_value
                  end
                end
              end
            end

            if expected_response['body']
              it "has a matching body" do
                expect(response_body).to match_term expected_response_body
              end
            end
          end
        end

        def description_for interaction
          "#{interaction.description} using #{interaction.request.method.upcase} to #{interaction.request.path}"
        end

        def read_pact_from uri, options = {}
          Pact::PactFile.read(uri, options)
        end

      end

      # The "arrange" and "act" parts of the test really only need to be run once,
      # however, stubbing is not supported in before :all, so this is a
      # wee hack to enable before :all like functionality using before :each.
      # In an ideal world, the test setup and execution should be quick enough for
      # the difference between :all and :each to be unnoticable, but the annoying
      # reality is, sometimes it does make a difference. This is for you, V!

      class InteractionContext

        attr_accessor :last_response

        def initialize
          @already_run = []
        end

        def run_once id
          unless @already_run.include?(id)
            yield
            @already_run << id
          end
        end

      end
    end
  end
end

