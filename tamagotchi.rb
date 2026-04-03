# frozen_string_literal: true

require 'json'
require 'io/console'

# ─── ANSI colours ───────────────────────────────────────────────────────────
module Color
  RESET  = "\e[0m"
  BOLD   = "\e[1m"
  RED    = "\e[31m"
  GREEN  = "\e[32m"
  YELLOW = "\e[33m"
  CYAN   = "\e[36m"
  BLUE   = "\e[34m"
  MAGENTA = "\e[35m"
  WHITE  = "\e[97m"
  GRAY   = "\e[90m"

  def self.color(code, text) = "#{code}#{text}#{RESET}"
  def self.bold(text)        = color(BOLD, text)
  def self.red(text)         = color(RED, text)
  def self.green(text)       = color(GREEN, text)
  def self.yellow(text)      = color(YELLOW, text)
  def self.cyan(text)        = color(CYAN, text)
  def self.blue(text)        = color(BLUE, text)
  def self.magenta(text)     = color(MAGENTA, text)
  def self.white(text)       = color(WHITE, text)
  def self.gray(text)        = color(GRAY, text)
end

# ─── Pet ────────────────────────────────────────────────────────────────────
class Pet
  STAGES      = %i[egg baby child teen adult].freeze
  SAVE_FILE   = 'tamagotchi_save.json'

  MAX_STAT    = 100
  TICK_SECS   = 30   # real seconds per game-tick
  AGE_PER_TICK = 1

  STAGE_AGE = { egg: 0..1, baby: 2..5, child: 6..12, teen: 13..20, adult: 21..Float::INFINITY }.freeze

  SPRITES = {
    egg:   ["  .--.  ", " (o  o) ", "  \\--/  ", "  (  )  "],
    baby:  ["  (^_^) ", " /|  |\\  ", "  /  \\  ", " ~BABY~ "],
    child: ["  (>_<) ", " /|  |\\ ", " / \\/\\ \\", "~CHILD~ "],
    teen:  ["  (o_O) ", "--|  |--", " /    \\ ", "~TEEN~  "],
    adult: ["  (^‿^) ", "--|  |--", " /    \\ ", "~ADULT~ "]
  }.freeze

  MOODS = {
    (80..100) => { label: 'Щасливий 😄', color: :green },
    (50..79)  => { label: 'Нормально 🙂', color: :cyan },
    (20..49)  => { label: 'Сумний 😕', color: :yellow },
    (0..19)   => { label: 'Нещасний 😢', color: :red }
  }.freeze

  attr_reader :name, :hunger, :energy, :mood, :age, :stage, :alive, :log

  def initialize(name)
    @name    = name
    @hunger  = 70   # 0 = starving, 100 = full
    @energy  = 80
    @mood    = 60
    @age     = 0
    @stage   = :egg
    @alive   = true
    @log     = []
    @last_tick = Time.now

    push_log "#{Color.magenta('✨')} #{@name} з'явився на світ!"
  end

  # ── Actions ───────────────────────────────────────────────────────────────

  def feed(amount = 25)
    return dead_msg unless alive?

    if hunger >= 95
      push_log "#{Color.yellow('🍔')} #{name} вже ситий — не перегодовуй!"
      return
    end

    delta = [amount, MAX_STAT - @hunger].min
    @hunger += delta
    @mood   = clamp(@mood + 5)
    push_log "#{Color.green('🍎')} Ти погодував #{name} (+#{delta} ситість, +5 настрій)"
  end

  def play(duration = 20)
    return dead_msg unless alive?

    if energy < 15
      push_log "#{Color.red('😴')} #{name} занадто втомлений, щоб гратися!"
      return
    end

    @mood   = clamp(@mood + duration)
    @energy = clamp(@energy - 15)
    @hunger = clamp(@hunger - 10)
    push_log "#{Color.cyan('🎮')} Ти пограв з #{name}! (+#{duration} настрій, -15 енергія)"
  end

  def sleep_pet(hours = 40)
    return dead_msg unless alive?

    if energy >= 95
      push_log "#{Color.yellow('💤')} #{name} не хоче спати — він бадьорий!"
      return
    end

    delta = [hours, MAX_STAT - @energy].min
    @energy  = clamp(@energy + delta)
    @hunger  = clamp(@hunger - 15)
    push_log "#{Color.blue('🌙')} #{name} поспав і відновив сили (+#{delta} енергія)"
  end

  def medicine
    return dead_msg unless alive?

    @mood   = clamp(@mood + 15)
    @energy = clamp(@energy + 10)
    push_log "#{Color.magenta('💊')} Ти дав ліки #{name} (+15 настрій, +10 енергія)"
  end

  # ── Tick (passive decay) ──────────────────────────────────────────────────

  def tick!
    return unless alive?

    now     = Time.now
    elapsed = ((now - @last_tick) / TICK_SECS).floor
    return if elapsed < 1

    elapsed.times { apply_decay }
    @last_tick = now
  end

  def apply_decay
    @hunger  = clamp(@hunger - rand(4..7))
    @energy  = clamp(@energy - rand(2..5))
    @mood    = clamp(@mood - rand(2..4))
    @age    += AGE_PER_TICK
    update_stage!
    check_death!
  end

  # ── Persistence ───────────────────────────────────────────────────────────

  def save!
    data = {
      name: @name, hunger: @hunger, energy: @energy,
      mood: @mood, age: @age, stage: @stage.to_s,
      alive: @alive, last_tick: @last_tick.to_f,
      log: @log.last(20)
    }
    File.write(SAVE_FILE, JSON.pretty_generate(data))
    push_log "#{Color.gray('💾')} Гру збережено."
  end

  def self.load!
    return nil unless File.exist?(SAVE_FILE)

    data = JSON.parse(File.read(SAVE_FILE), symbolize_names: true)
    pet  = allocate
    pet.send(:restore, data)
    pet
  rescue JSON::ParserError
    nil
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def alive? = @alive

  def mood_info
    MOODS.each { |range, info| return info if range.include?(@mood.round) }
    MOODS.values.last
  end

  def stage_sprite = SPRITES[@stage]

  def stat_bar(value, width = 20)
    filled = (value / MAX_STAT.to_f * width).round
    green  = filled > width * 0.6 ? filled : 0
    yellow = filled > width * 0.3 && green == 0 ? filled : 0
    red    = (green == 0 && yellow == 0) ? filled : 0

    bar = Color.green('█' * green) +
          Color.yellow('█' * yellow) +
          Color.red('█' * red) +
          Color.gray('░' * (width - filled))
    "[#{bar}] #{value.round}%"
  end

  private

  def clamp(v) = [[v.round, 0].max, MAX_STAT].min

  def push_log(msg)
    @log << "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
    @log = @log.last(15)
  end

  def dead_msg
    push_log Color.red("💀 #{name} вже не з нами...")
  end

  def update_stage!
    STAGE_AGE.each do |stage, range|
      if range.include?(@age)
        if @stage != stage
          @stage = stage
          push_log "#{Color.magenta('🌟')} #{name} виріс! Тепер він: #{stage.upcase}"
        end
        break
      end
    end
  end

  def check_death!
    if @hunger <= 0 || @energy <= 0
      @alive = false
      push_log Color.red("💀 #{name} помер від виснаження... Спочивай з миром.")
    elsif @mood <= 0
      @alive = false
      push_log Color.red("💀 #{name} помер від суму... Будь уважнішим наступного разу.")
    end
  end

  def restore(data)
    @name      = data[:name]
    @hunger    = data[:hunger]
    @energy    = data[:energy]
    @mood      = data[:mood]
    @age       = data[:age]
    @stage     = data[:stage].to_sym
    @alive     = data[:alive]
    @last_tick = Time.at(data[:last_tick])
    @log       = data[:log] || []
  end
end

# ─── UI ─────────────────────────────────────────────────────────────────────
class TamagotchiUI
  MENU = [
    ['1', '🍎 Годувати',    :feed],
    ['2', '🎮 Гратися',     :play],
    ['3', '🌙 Спати',       :sleep_pet],
    ['4', '💊 Ліки',        :medicine],
    ['5', '⏭  Пропустити тік (тест)', :force_tick],
    ['S', '💾 Зберегти',   :save],
    ['Q', '🚪 Вийти',       :quit]
  ].freeze

  def initialize(pet)
    @pet  = pet
    @running = true
  end

  def run
    while @running
      @pet.tick!
      render
      handle_input
    end
  end

  private

  def render
    system('clear') || system('cls')
    print_header
    print_sprite
    print_stats
    print_log
    print_menu
  end

  def print_header
    puts Color.bold(Color.cyan("╔══════════════════════════════════════╗"))
    puts Color.bold(Color.cyan("║        🐣  TAMAGOTCHI  🐣             ║"))
    puts Color.bold(Color.cyan("╚══════════════════════════════════════╝"))
    puts
  end

  def print_sprite
    info = @pet.mood_info
    mood_str = Color.send(info[:color], info[:label])

    puts "  #{Color.bold(@pet.name.upcase)}  |  Вік: #{@pet.age}  |  Стадія: #{@pet.stage.upcase}"
    puts "  Настрій: #{mood_str}"
    puts
    @pet.stage_sprite.each { |line| puts "    #{Color.yellow(line)}" }
    puts
    unless @pet.alive?
      puts Color.red("  ☠️  #{@pet.name} помер. Натисни Q для виходу або N для нової гри.")
    end
    puts
  end

  def print_stats
    puts Color.bold("  📊 Стан:")
    puts "  Ситість  #{@pet.stat_bar(@pet.hunger)}"
    puts "  Енергія  #{@pet.stat_bar(@pet.energy)}"
    puts "  Настрій  #{@pet.stat_bar(@pet.mood)}"
    puts
  end

  def print_log
    puts Color.bold("  📜 Журнал:")
    @pet.log.last(5).each { |line| puts "  #{Color.gray(line)}" }
    puts
  end

  def print_menu
    puts Color.bold("  ── Дії ──────────────────────────────────")
    MENU.each do |key, label, _|
      puts "  #{Color.cyan("[#{key}]")} #{label}"
    end
    print Color.bold("\n  Твій вибір: ")
  end

  def handle_input
    input = $stdin.gets&.strip&.upcase
    return unless input

    if input == 'Q'
      @pet.save!
      @running = false
      puts Color.green("\nДо побачення! #{@pet.name} чекатиме на тебе 🐾\n")
    elsif input == 'N' && !@pet.alive?
      @running = false
    elsif input == '5'
      @pet.apply_decay
    elsif input == 'S'
      @pet.save!
    else
      action = MENU.find { |k, _, _| k == input }&.last
      @pet.send(action) if action && !%i[save quit force_tick].include?(action)
    end
  end
end

# ─── Entry point ────────────────────────────────────────────────────────────
def main
  system('clear') || system('cls')
  puts Color.bold(Color.cyan(<<~BANNER))
    ╔══════════════════════════════════════╗
    ║   🐣  Ласкаво просимо до Tamagotchi  ║
    ╚══════════════════════════════════════╝
  BANNER

  pet = Pet.load!

  if pet
    puts "  Знайдено збережену гру з #{Color.bold(pet.name)}!"
    print "  Продовжити? (Y/n): "
    answer = $stdin.gets.strip.downcase
    pet = nil if answer == 'n'
  end

  unless pet
    print "\n  Як назвеш свого вихованця? "
    name = $stdin.gets.strip
    name = 'Тамагоша' if name.empty?
    pet = Pet.new(name)
  end

  TamagotchiUI.new(pet).run
end

main
