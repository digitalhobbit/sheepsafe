require 'rspec'
require 'sheepsafe'

describe Sheepsafe::Controller do
  let(:config) do
    double("config", :trusted_location => "trusted_location", :untrusted_location => "untrusted_location",
         :last_network= => nil, :write => nil)
  end

  let (:network) do
    double("network", :up? => true, :ssid => "current", :bssid => "current_bssid")
  end

  let(:controller) do
    # Stub out logging
    Sheepsafe::Controller.new(config, network, double("logger", :info => nil)).tap do |c|
      c.stub(:notify_ok)
      c.stub(:notify_warning)
    end
  end

  context "#network_changed?" do
    it "is when the current_network is different than the last_network" do
      config.stub!(:last_network).and_return double("network", :ssid => "last", :bssid => nil)
      controller.network_changed?.should be_true
    end

    it "is when there is no last network" do
      config.stub!(:last_network).and_return nil
      controller.network_changed?.should be_true
    end
  end

  context "#switch_to_trusted?" do
    it "is when the current network is trusted" do
      network.stub :trusted? => true
      controller.switch_to_trusted?.should be_true
    end
  end

  context "#switch_to_untrusted?" do
    it "is when the current network is trusted" do
      network.stub :trusted? => false
      controller.switch_to_untrusted?.should be_true
    end
  end

  context "network didn't change" do
    before :each do
      config.stub :last_network => network
    end

    it "does nothing" do
      config.should_not_receive(:write)
      controller.run
    end
  end

  context "network is down" do
    it "does nothing" do
      network.should_receive(:up?).and_return false
      config.should_not_receive(:write)
      controller.run
    end
  end

  context "network changed" do
    before :each do
      controller.stub(:network_changed? => true, :switch_to_trusted? => false,
                      :switch_to_untrusted? => false)
    end

    it "writes the last network to the configuration" do
      config.should_receive(:last_network=).ordered
      config.should_receive(:write).ordered
      controller.run
    end

    context "to trusted" do
      it "changes to the trusted location" do
        controller.should_receive(:switch_to_trusted?).and_return true
        controller.should_receive(:system).with("scselect trusted_location")
        controller.should_receive(:bring_socks_proxy).with('down')
        controller.run
      end
    end

    context "to untrusted" do
      it "changes to the untrusted location" do
        controller.should_receive(:switch_to_untrusted?).and_return true
        controller.should_receive(:system).with("scselect untrusted_location")
        controller.should_receive(:bring_socks_proxy).with('up')
        controller.run
      end
    end
  end
end

describe Sheepsafe::Network do
  let(:current_network) { Sheepsafe::Network.new }

  context "with trusted SSID" do
    let(:config) { Sheepsafe::Config.new({"trusted_names" => [current_network.ssid]}) }
    subject { Sheepsafe::Network.new(config) }

    it { should be_trusted }
  end

  context "with trusted BSSID" do
    let(:config) { Sheepsafe::Config.new({"trusted_names" => [current_network.bssid]}) }
    subject { Sheepsafe::Network.new(config) }

    it { should be_trusted }
  end

  context "with no trusted names" do
    subject { Sheepsafe::Network.new }

    it { should_not be_trusted }
  end
end

describe Sheepsafe::Installer do
  let(:config) { double("config").as_null_object }
  let(:network) { double("network", :up? => true, :ssid => "current", :bssid => "current_bssid") }
  let(:controller) { double "controller" }
  let (:installer) do
    @messages = []
    @commands = []
    Sheepsafe::Installer.new(config, network, controller).tap do |ins|
      ins.stub(:say).and_return do |msg|
        @messages << msg
      end
      ins.stub(:ask).and_return do |msg,*rest|
        @messages << msg
        ""
      end
      ins.stub(:agree).and_return do |msg|
        @messages << msg
        true
      end
      ins.stub(:system).and_return do |cmd|
        @commands << cmd
        nil
      end
    end
  end

  before :each do
    $?.stub :success? => true
  end

  it "asks questions, runs commands, writes the config to disk and runs the controller" do
    config.should_receive(:write)
    controller.should_receive(:run)
    installer.should_receive(:write_launchd_plist) # don't want to actually touch plist file
    installer.install
    @messages.should_not be_empty
    @commands.should_not be_empty
  end
end
