# frozen_string_literal: true

module SurSolver
  # Base of every error the client raises. Messages never contain the API key.
  class Error < StandardError
    # The call that failed ("createTask", "getTaskResult", "getBalance", "listTaskTypes",
    # "listServices"); nil for ConfigurationError and SolveTimeoutError.
    attr_reader :operation

    def initialize(message, operation: nil)
      super(message)
      @operation = operation
    end
  end

  # The client was built with an unusable option. Nothing was sent.
  class ConfigurationError < Error; end

  # No usable answer: a connection failure, a timeout, a non-200 status, or a body that is not the
  # API's envelope. It says nothing about the task.
  class TransportError < Error
    # The HTTP status when a response arrived, otherwise nil.
    attr_reader :status
    # error.code of the API's internal envelope, or nil.
    attr_reader :server_code
    # error.retry_after_seconds of the internal envelope, or nil.
    attr_reader :retry_after_seconds

    def initialize(operation, reason, status: nil, server_code: nil, retry_after_seconds: nil)
      note = operation == "createTask" ? " The task may have been created and charged; check get_balance before submitting again." : ""
      super("#{operation} failed: #{reason}.#{note}", operation: operation)
      @status = status
      @server_code = server_code
      @retry_after_seconds = retry_after_seconds
    end

    # True for createTask: the request may have been accepted and charged before the answer was
    # lost. Check get_balance before submitting again.
    def may_have_created_task?
      operation == "createTask"
    end
  end

  # HTTP 200 JSON whose shape the API contract does not allow.
  class ProtocolError < Error
    def initialize(operation, detail)
      super("#{operation} returned an unexpected response: #{detail}", operation: operation)
    end
  end

  # solve reached its deadline. The task may still finish and stays charged; poll it with
  # get_task_result(task_id) if you still need the result.
  class SolveTimeoutError < Error
    attr_reader :task_id, :timeout, :last_error

    def initialize(task_id, timeout, last_error)
      super("task #{task_id} was not ready within #{timeout} s; it may still finish and stays charged")
      @task_id = task_id
      @timeout = timeout
      @last_error = last_error
    end
  end

  # The API answered errorId 1. Rescue the subclasses for the codes you handle; ApiError itself
  # means ERROR_INTERNAL_ERROR, ERROR_FAILED on create, or a code newer than this gem.
  class ApiError < Error
    # The errorCode exactly as sent, including codes newer than this gem.
    attr_reader :code
    # The errorDescription as sent.
    attr_reader :description
    # The task for get_task_result and for solve after acceptance, otherwise nil.
    attr_reader :task_id
    # The list sent with ERROR_WRONG_USERAGENT; empty otherwise.
    attr_reader :supported_user_agents

    def initialize(operation, code, description, task_id: nil, supported_user_agents: [])
      super("#{code}: #{description}#{task_id ? " (task #{task_id})" : ""}", operation: operation)
      @code = code
      @description = description
      @task_id = task_id
      @supported_user_agents = supported_user_agents.freeze
    end

    # True only for ERROR_NO_SLOT_AVAILABLE.
    def retryable?
      code == ErrorCodes::ERROR_NO_SLOT_AVAILABLE
    end
  end

  # ERROR_WRONG_CLIENT_KEY or ERROR_KEY_DOES_NOT_EXIST: fix the API key.
  class AuthenticationError < ApiError; end

  # ERROR_INVALID_REQUEST, ERROR_TYPE_NOT_SUPPORTED, or ERROR_WRONG_USERAGENT on create (see
  # supported_user_agents). Nothing was created or charged.
  class InvalidTaskError < ApiError; end

  # ERROR_ZERO_BALANCE: top up. Nothing was charged.
  class InsufficientBalanceError < ApiError; end

  # ERROR_NO_SLOT_AVAILABLE: all your threads are busy. Nothing was created; submitting later is safe.
  class NoSlotAvailableError < ApiError; end

  # ERROR_TASK_NOT_FOUND.
  class TaskNotFoundError < ApiError; end

  # The task ended without a result (ERROR_FAILED, ERROR_TASK_TIMEOUT, ERROR_TASK_EXPIRED, or
  # ERROR_WRONG_USERAGENT after acceptance). Its charge is returned once.
  class TaskFailedError < ApiError; end

  class ApiError
    TASK_FAILURE_CODES = [
      ErrorCodes::ERROR_FAILED, ErrorCodes::ERROR_TASK_TIMEOUT, ErrorCodes::ERROR_TASK_EXPIRED,
      ErrorCodes::ERROR_WRONG_USERAGENT
    ].freeze

    CLASS_BY_CODE = {
      ErrorCodes::ERROR_WRONG_CLIENT_KEY => AuthenticationError,
      ErrorCodes::ERROR_KEY_DOES_NOT_EXIST => AuthenticationError,
      ErrorCodes::ERROR_INVALID_REQUEST => InvalidTaskError,
      ErrorCodes::ERROR_TYPE_NOT_SUPPORTED => InvalidTaskError,
      ErrorCodes::ERROR_WRONG_USERAGENT => InvalidTaskError,
      ErrorCodes::ERROR_ZERO_BALANCE => InsufficientBalanceError,
      ErrorCodes::ERROR_NO_SLOT_AVAILABLE => NoSlotAvailableError,
      ErrorCodes::ERROR_TASK_NOT_FOUND => TaskNotFoundError
    }.freeze

    # The error for a code; the class depends on the operation and the code.
    def self.for(operation, code, description, task_id, supported)
      klass = if operation == "getTaskResult" && TASK_FAILURE_CODES.include?(code)
                TaskFailedError
              else
                CLASS_BY_CODE.fetch(code, ApiError)
              end
      klass.new(operation, code, description, task_id: task_id, supported_user_agents: supported)
    end
  end
end
