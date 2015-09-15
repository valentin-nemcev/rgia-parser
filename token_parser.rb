
class TokenEntry
  def to_yaml
    result = Hash.new([])
    result[:full_name] = full_name
    tag_tokens.inject(result) { |h, a| h[a.type] += [a.value]; h }
  end

  def fill_from_prev(prev)
  end

  def fill_from_next(n)
  end

end


class TokenAuthor < TokenEntry
  attr_accessor :initials_before_surname
  attr_reader :name_tokens

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
    i = name_tokens.index(name_chunk.first)
    name_tokens.insert(i, *tokens) unless i.nil?
  end

  def insert_name_tokens_after_initials(tokens)
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

  def surname_word
    if proper_name_tokens.empty? && initial_tokens.present? && (word_tokens.size == 1)
      word_tokens.first
    end
  end

  def full_name
    surname_word = self.surname_word
    values = if surname_word.present?
      name_tokens
        .select{ |t| t.type.in? [:initial, :proper_name, :word] }
        .map { |t| t == surname_word ? Unicode::capitalize(t.value) : t.value }
    else
      name_chunk.map(&:value)
    end
    values.join('')
  end

  def empty?
    name_chunk.empty?
  end

  def suspicious?
    name_chunk.select{ |t| t.type == :proper_name }.count != 1
  end

  def fill_from_prev(prev_author)
    return unless prev_author.kind_of?(TokenAuthor) && proper_name_tokens.empty?

    if prev_author.initials_after_surname?
      self.insert_name_tokens_before_initials(prev_author.proper_name_tokens)
    end
  end

  def fill_from_next(next_author)
    return unless next_author.kind_of?(TokenAuthor) && proper_name_tokens.empty?

    if next_author.initials_before_surname?
      self.insert_name_tokens_after_initials(next_author.proper_name_tokens)
    end
  end

end


class TokenCompany < TokenEntry

  attr_reader :name_tokens, :tag_tokens
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

  def suspicious?
    type.blank?
  end

  def empty?
    name_tokens.empty?
  end


  def full_name
    name_started = false
    name_tokens.map do |token|
      if token.type == :company_type && !name_started
        token.value + ' '
      elsif token.type != :open_quote
        name_started = true
        token.matched
      else
        token.matched
      end
    end.join('').strip
  end

end


class TokenParser

  attr_accessor :subject_tokens
  attr_reader :authors

  def initialize(subject_tokens)
    @subject_tokens = subject_tokens
    @authors = []
  end

  # attr_reader :tags
  def reset_author
    @author = nil
    @company = nil
    # @tags = []
  end

  def company_present?
    @company.present?
  end

  def author_present?
    not (@author.nil? || @author.empty?)
  end

  def company
    @company ||=
      begin
        authors.push(@company = TokenCompany.new)
        # @company.tags = @tags
        @company
      end
  end

  def author
    @author ||=
      begin
        authors.push(@author = TokenAuthor.new)
        # @author.tags = @tags
        @author
      end
  end

  def replace_author_with_company
    return unless @author == authors.last
    author = authors.pop
    reset_author
    company.add_name_token(*author.name_tokens) if author.present?
    company.add_tag_tokens(author.tag_tokens) if author.present?
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
        # when :occupation, :position, :citizenship, :location
        #   # reset_author
        #   tags << token
        when :company_type, :open_quote
          if author_present?
            reset_author
          else
            replace_author_with_company
          end
          company.add_name_token token
        when :connector
          reset_author if author_present?
        else
          author.add_name_token token
        end
      end
    end
    fill_authors
    authors.pop if authors.size > 1 && authors.last.empty?
    {:authors => authors}
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
