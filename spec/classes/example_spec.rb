require 'spec_helper'

describe 'preview' do
  context 'supported operating systems' do
    ['Debian', 'RedHat'].each do |osfamily|
      describe "preview class without any parameters on #{osfamily}" do
        let(:params) {{ }}
        let(:facts) {{
          :osfamily => osfamily,
        }}

        it { should compile.with_all_deps }

        it { should contain_class('preview::params') }
        it { should contain_class('preview::install').that_comes_before('preview::config') }
        it { should contain_class('preview::config') }
        it { should contain_class('preview::service').that_subscribes_to('preview::config') }

        it { should contain_service('preview') }
        it { should contain_package('preview').with_ensure('present') }
      end
    end
  end

  context 'unsupported operating system' do
    describe 'preview class without any parameters on Solaris/Nexenta' do
      let(:facts) {{
        :osfamily        => 'Solaris',
        :operatingsystem => 'Nexenta',
      }}

      it { expect { should contain_package('preview') }.to raise_error(Puppet::Error, /Nexenta not supported/) }
    end
  end
end
