require 'rails_helper'
require 'timeout'

RSpec.describe 'bin/purge-scheduler' do
  it 'keeps running the purge after a failed run and stops cleanly on TERM' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'bin'))
      FileUtils.cp(Rails.root.join('bin/purge-scheduler'), File.join(dir, 'bin'))
      calls = File.join(dir, 'calls.log')
      fake_rails = File.join(dir, 'bin/rails')
      File.write(fake_rails, "#!/usr/bin/env bash\necho \"$*\" >> #{calls}\nexit 1\n")
      File.chmod(0o755, fake_rails)

      pid = Process.spawn({ 'PURGE_INTERVAL_SECONDS' => '0.1' }, File.join(dir, 'bin/purge-scheduler'),
                          chdir: dir, err: File::NULL)
      begin
        Timeout.timeout(5) { sleep 0.05 until File.exist?(calls) && File.readlines(calls).size >= 2 }
        Process.kill('TERM', pid)
        _, status = Timeout.timeout(5) { Process.wait2(pid) }
        pid = nil

        expect(status).to be_success
        expect(File.readlines(calls, chomp: true)).to all(eq('tokens:purge'))
      ensure
        if pid
          Process.kill('KILL', pid)
          Process.wait(pid)
        end
      end
    end
  end
end
