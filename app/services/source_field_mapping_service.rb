class SourceFieldMappingService
  BASE_FIELD_MAPPING = {
    'id' => 'external_id',
    'subject' => 'subject',
    'description' => 'description',
    'status' => 'status',
    'priority' => 'priority',
    'assignee' => 'assignee',
    'reporter' => 'reporter',
    'tracker' => 'tracker',
    'created' => 'created_on',
    'updated' => 'updated_on',
    'due date' => 'due_date',
    'parent task' => 'parent_issue',
    'attachment' => 'attachment',
    'attachments' => 'attachment',
    'comment' => 'comment',
    'comments' => 'comment'
  }.freeze

  def initialize(source_type)
    @source_type = source_type.to_s.downcase
  end

  def get_mapping
    case @source_type
    when 'jira'
      jira_mapping
    when 'clickup'
      clickup_mapping
    when 'asana'
      asana_mapping
    when 'trello'
      trello_mapping
    when 'monday'
      monday_mapping
    else
      BASE_FIELD_MAPPING
    end
  end

  private

  def jira_mapping
    BASE_FIELD_MAPPING.merge({
      'jira id' => 'external_id'
    })
  end

  def clickup_mapping
    BASE_FIELD_MAPPING.merge({
      'task id' => 'external_id',
      'task name' => 'subject',
      'list' => 'project',
      'folder' => 'category',
      'space' => 'version',
      'assignees' => 'assignee',
      'tags' => 'category'
    })
  end

  def asana_mapping
    BASE_FIELD_MAPPING.merge({
      'task id' => 'external_id',
      'task name' => 'subject',
      'project' => 'project',
      'section' => 'category',
      'completed' => 'status',
      'completed at' => 'closed_on',
      'assignee' => 'assignee',
      'tags' => 'category'
    })
  end

  def trello_mapping
    BASE_FIELD_MAPPING.merge({
      'card id' => 'external_id',
      'card name' => 'subject',
      'list name' => 'status',
      'board name' => 'project',
      'labels' => 'category',
      'members' => 'assignee',
      'date created' => 'created_on',
      'date last activity' => 'updated_on'
    })
  end

  def monday_mapping
    BASE_FIELD_MAPPING.merge({
      'item id' => 'external_id',
      'item name' => 'subject',
      'group' => 'category',
      'board' => 'project',
      'person' => 'assignee',
      'timeline' => 'due_date',
      'creation log' => 'created_on'
    })
  end
end