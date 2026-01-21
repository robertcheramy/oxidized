class ApcOS < Oxidized::Model
  using Refinements

  # Prompt can be short (apc>) or long (username@apc>)
  prompt /^(:?\S+@)?apc>/
  comment '; '

  def clean(cfg)
    cfg = cfg.cut_both(2, 1)
    cfg.gsub("\r", "")
  end

  cmd 'about' do |cfg|
    cfg = clean(cfg)
    cfg = cfg.reject_lines [/^Management Uptime: /, /^Date: /, /^Time: /]
    comment cfg
  end

  cmd 'upsabout' do |cfg|
    cfg = clean(cfg)
    comment cfg
  end

  cmd 'detstatus -ss' do |cfg|
    cfg = clean(cfg)
    comment cfg
  end

  cmd 'config.ini', input: :scp do |cfg|
    "; ========== config.ini ==========\n" + cfg
  end

  cfg :ssh do
    pre_logout 'exit'
  end
end
