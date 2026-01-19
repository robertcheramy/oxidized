class ApcOS < Oxidized::Model
  using Refinements

  # Prompt can be short (apc>) or long (username@apc>)
  prompt /^(:?\S+@)?apc>/
  comment '; '

  cmd 'about' do |cfg|
    comment cfg
  end

  cmd 'upsabout' do |cfg|
    comment cfg
  end

  cmd 'detstatus -ss' do |cfg|
    comment cfg
  end

  cmd 'config.ini', input: :scp do |cfg|
    cfg
  end

  cfg :ssh do
    pre_logout 'exit'
  end
end
