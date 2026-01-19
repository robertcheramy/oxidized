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
    Oxidized::SSH.any_instance.expects(:cmd)
                 .with("about").returns("about result\n")
    Oxidized::SSH.any_instance.expects(:cmd)
                 .with("upsabout").returns("upsabout result\n")
    Oxidized::SSH.any_instance.expects(:cmd)
                 .with("detstatus -ss")
                 .returns("detstatus -ss result\n")
    Oxidized::SSH.any_instance.expects(:cmd)
                 .with("config.ini", input: :scp)
                 .returns("config.ini content\n")

    status, result = @node.run

    _(status).must_equal :success
    _(result.to_cfg).must_equal "; about result\n; upsabout result\n" \
                                "; detstatus -ss result\nconfig.ini content\n"
  end
end
