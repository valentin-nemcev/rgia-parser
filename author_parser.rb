
class Author
  def to_yaml
    result = Hash.new([])
    result[:full_name] = full_name
    tag_tokens.inject(result) { |h, a| h[a.type] += [a.value]; h }
  end

  def fill_from_prev(prev)
  end

  def fill_from_next(n)
  end

  def tags_for(type)
    tag_tokens.select{ |t| t.type == type }.map(&:value)
  end

end


class Person < Author
  attr_accessor :initials_before_surname, :reused_name_tokens
  attr_reader :name_tokens

  def person?
    true
  end

  def initialize
    @name_tokens = []
  end

  def add_name_token(token)
    name_tokens.push token
  end

  def initials_before_surname?
    name_chunk.first.try(:type) == :initial
  end

  def initials_after_surname?
    name_chunk.last.try(:type) == :initial
  end

  def insert_name_tokens_before_initials(tokens)
    self.reused_name_tokens = true
    i = name_tokens.index(name_chunk.first)
    name_tokens.insert(i, *tokens) unless i.nil?
  end

  def insert_name_tokens_after_initials(tokens)
    self.reused_name_tokens = true
    i = name_tokens.index(name_chunk.last) + 1
    name_tokens.insert(i, *tokens) unless i.nil?
  end

  def tag_tokens
    name_tokens
      .select{ |t| t.type.in? [:occupation, :position, :citizenship, :location] }
  end

  def name_chunk
    name_tokens
      .chunk{ |t| t.type.in? [:initial, :proper_name] }
      .reverse_each
      .find{ |chunk| chunk.first == true }
      .try(:second) || []
  end

  def proper_name_tokens
    name_chunk.select{ |t| t.type == :proper_name }
  end

  def word_tokens
    name_tokens.select{ |t| t.type == :word }
  end

  def initial_tokens
    name_tokens.select{ |t| t.type == :initial }
  end

  def unknown_tokens
    name_tokens.select(&:unknown?).reject{ |t| t == surname_word }
  end

  def surname_word
    if proper_name_tokens.empty? && initial_tokens.present? && (word_tokens.size == 1)
      word_tokens.first
    end
  end

  def lemmatize(surname)
    if reused_name_tokens
      nom = surname.sub(/(ам|ым) $/, ' ').sub(/ким $/, 'кий ')
      return nom if nom != surname
    end
    @petrovich ||= Petrovich.new(:male )
    surname.strip.split('-').map do |s|
      if s.size <= 2
        s
      else
        nom = @petrovich.lastname(s, :nominative, :dative)
        nom.sub!(/ок$/, 'к')
        nom[-1, 1] == 'я' ? s : nom
      end
    end.join('-') + ' '
  end

  def full_name_tokens
    surname_word = self.surname_word
    if surname_word.present?
      name_tokens
        .select{ |t| t.type.in? [:initial, :proper_name, :word] }
        .map do |t|
          value = t == surname_word ? Unicode::capitalize(t.value) : t.value
          value = t.type != :initial ? lemmatize(value) : value
          Token.new(t.type == :initial ? :initial : :proper_name, value, value)
        end
    else
      name_chunk.map do |t|
        value = t.type != :initial ? lemmatize(t.value) : t.value
        Token.new(t.type, value, value)
      end
    end
  end

  def full_name
    full_name_tokens.map(&:value).join('')
  end

  def empty?
    name_chunk.empty?
  end

  def fill_from_prev(prev_author)
    return unless prev_author.kind_of?(Person) && proper_name_tokens.empty?

    if prev_author.initials_after_surname?
      self.insert_name_tokens_before_initials(prev_author.proper_name_tokens)
      prev_author.reused_name_tokens = true
    end
  end

  def fill_from_next(next_author)
    return unless next_author.kind_of?(Person) && proper_name_tokens.empty?

    if next_author.initials_before_surname?
      self.insert_name_tokens_after_initials(next_author.proper_name_tokens)
      next_author.reused_name_tokens = true
    end
  end


  def validate(title)
    if unknown_tokens.select(&:suspicious?).present?
      title.warn "Name contains suspicious unknown tokens"
    end

    if full_name_tokens.select{ |t| t.type == :proper_name }.any?(&:adjective?)
      title.warn "Suspicious surname"
    end
    # title.warn "Possible inflection problems" if reused_name_tokens
    if name_chunk.chunk(&:type).count > 2
      title.warn "Suspicious initial ordering"
    end
    title.warn "Missing surname" if author.blank?
  end


  def author
    full_name_tokens.select{ |t| t.type == :proper_name }.map(&:value).join('')
  end

  def author_initials
    full_name_tokens.select{ |t| t.type == :initial }.map(&:value).join('')
  end

  def author_name
    ''
  end

  def author_patronymic
    ''
  end

end


class Company < Author

  extend Memoist

  attr_reader :name_tokens, :tag_tokens

  def person?
    false
  end

  def initialize
    @name_tokens = []
    @tag_tokens = []
  end

  def add_name_token(*token)
    name_tokens.push(*token)
    self
  end

  def add_tag_tokens(tokens)
    tag_tokens.push(*tokens)
  end

  def type
    name_tokens.find{ |t| t.type == :company_type }
  end

  def empty?
    name_tokens.empty?
  end

  def full_name
    full_name_with_type[:name]
  end

  def unknown_tokens
    full_name_with_type[:unknown_tokens_with_type]
      .slice(0...-1).select(&:unknown?)
  end

  def unknown_tokens_with_type
    full_name_with_type[:unknown_tokens_with_type]
  end


  def full_name_with_type
    name_started = false
    nominative_type = false
    unknown_tokens_with_type = nil
    name = name_tokens.each_with_index.map do |token, i|
      if token.type == :company_type 
        if !name_started
          nominative_type = true
          unknown_tokens_with_type ||= []
          token.value + ' '
        else
          unknown_tokens_with_type ||= name_tokens.slice(0..i)
          token.matched
        end
      elsif token.type == :open_quote
        token.matched
      # elsif !name_started && token.adjective?
      #   token.nominative_adjective
      elsif token.type == :connector
        token.matched
      else
        name_started = true
        token.matched
      end
    end.join('').strip
    {
      :name => name,
      :nominative_type => nominative_type,
      :unknown_tokens_with_type => unknown_tokens_with_type || []
    }
  end
  memoize :full_name_with_type


  def validate(title)
    if unknown_tokens.select(&:suspicious?).present?
      title.warn "Name contains suspicious unknown tokens"
    end

    title.warn "Possible inflection problems" unless full_name_with_type[:nominative_type]
  end

  def author
    full_name
  end

  def author_initials
    ''
  end

  def author_name
    ''
  end

  def author_patronymic
    ''
  end

end


class AuthorParser

  attr_accessor :subject_tokens
  attr_reader :authors

  def initialize(subject_tokens)
    @subject_tokens = subject_tokens
    @authors = []
  end

  def reset_author
    @person = nil
    @company = nil
  end

  def company_present?
    @company.present?
  end

  def person_present?
    not (@person.nil? || @person.empty?)
  end

  def company
    @company ||=
      begin
        authors.push(@company = Company.new)
        @company
      end
  end

  def person
    @person ||=
      begin
        authors.push(@person = Person.new)
        @person
      end
  end

  def replace_person_with_company
    return unless @person == authors.last
    person = authors.pop
    reset_author
    unless person.nil?
      company.add_tag_tokens(person.tag_tokens)
      company.add_name_token(*(person.name_tokens - person.tag_tokens))
    end
  end

  def parse
    reset_author
    subject_tokens.each_with_index do |token, i|
      next_token = subject_tokens[i + 1] || Token.empty
      prev_token = subject_tokens[i - 1] || Token.empty
      if company_present?
        case token.type
        when :duration
          reset_author
        when :close_quote
          company.add_name_token token
          reset_author unless next_token.type == :company_type_qualifier
        when :company_type_qualifier
          company.add_name_token token
          reset_author if prev_token.type == :close_quote
        else
          company.add_name_token token
        end
      else
        case token.type
        when :company_type, :open_quote
          if person_present?
            reset_author
          else
            replace_person_with_company
          end
          company.add_name_token token
        when :connector
          reset_author if person_present?
        else
          person.add_name_token token
        end
      end
    end
    fill_authors
    authors.pop if authors.size > 1 && authors.last.empty?
    authors
  end

  def fill_authors
    authors.each_cons(2) do |a1, a2|
      a2.fill_from_prev(a1)
    end
    authors.reverse.each_cons(2) do |a2, a1|
      a1.fill_from_next(a2)
    end
  end

end
