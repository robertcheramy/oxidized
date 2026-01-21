require_relative '../spec_helper'

describe 'Model apc_aos' do
  before(:each) do
    Oxidized.asetus = Asetus.new

    Oxidized::Node.any_instance.stubs(:resolve_repo)
    Oxidized::Node.any_instance.stubs(:resolve_output)
  end

  it "fetches the configuration with ssh and scp" do
    @node = Oxidized::Node.new(name:     'example.com',
                               input:    'ssh',
                               output:   'file',
                               model:    'apcos',
                               username: 'alma',
                               password: 'armud')
    Oxidized::SSH.any_instance.stubs(:connect).returns(true)
    Oxidized::SSH.any_instance.stubs(:node).returns(@node)
    Oxidized::SSH.any_instance.stubs(:connect_cli).returns(true)
    Oxidized::SSH.any_instance.stubs(:disconnect).returns(true)
    Oxidized::SSH.any_instance.stubs(:disconnect_cli).returns(true)
    model = YAML.load_file('spec/model/data/apcos#SMT750IC_v2.5.0.8#custom_simulation.yaml')

    commands = ["about", "upsabout", "detstatus -ss"]
    commands.each do |c|
      c_result = model['commands']["#{c}\n"]
      c_result = "\"#{c_result}\"".undump
      Oxidized::SSH.any_instance.expects(:cmd)
                   .with(c).returns(c_result)
    end
    Oxidized::SSH.any_instance.expects(:cmd)
                 .with("config.ini", input: :scp)
                 .returns(model['commands']['config.ini'])

    status, result = @node.run

    output = File.read('spec/model/data/apcos#SMT750IC_v2.5.0.8#custom_output.txt')
    _(status).must_equal :success
    _(result.to_cfg).must_equal output
  end
end
