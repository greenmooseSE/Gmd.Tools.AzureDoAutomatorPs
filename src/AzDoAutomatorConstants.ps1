<#
.SYNOPSIS
Azure DevOps Automator Constants Module

.DESCRIPTION
Defines constants used throughout Azure DevOps automation scripts including:
- API endpoints and versions
- Work item type names
- Field reference names
- Error codes and validation rules

.NOTES
This module should be dot-sourced by other automation scripts.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# API Configuration
# ============================================================================

# Azure DevOps API version and base URL pattern
[string]$script:AZDO_API_VERSION = '7.1-preview.3'
[string]$script:AZDO_API_BASE_URL = 'https://dev.azure.com/{organization}/{project}/_apis'
[string]$script:AZDO_WORKITEM_API_BASE = 'https://dev.azure.com/{organization}/{project}/_apis/wit/workitems'

# ============================================================================
# Work Item Types
# ============================================================================

# Standard work item type names
[string]$script:WORKITEM_TYPE_EPIC = 'Epic'
[string]$script:WORKITEM_TYPE_FEATURE = 'Feature'
[string]$script:WORKITEM_TYPE_STORY = 'User Story'
[string]$script:WORKITEM_TYPE_TASK = 'Task'
[string]$script:WORKITEM_TYPE_BUG = 'Bug'

# Valid work item types
[string[]]$script:VALID_WORKITEM_TYPES = @('Epic', 'Feature', 'Story', 'Task', 'Bug')

# ============================================================================
# Field Reference Names
# ============================================================================

# Core fields (system.*)
[string]$script:FIELD_SYSTEM_ID = 'System.Id'
[string]$script:FIELD_SYSTEM_TITLE = 'System.Title'
[string]$script:FIELD_SYSTEM_TYPE = 'System.WorkItemType'
[string]$script:FIELD_SYSTEM_STATE = 'System.State'
[string]$script:FIELD_SYSTEM_AREA = 'System.AreaPath'
[string]$script:FIELD_SYSTEM_ITERATION = 'System.IterationPath'
[string]$script:FIELD_SYSTEM_TAGS = 'System.Tags'

# Description and content fields
[string]$script:FIELD_DESCRIPTION = 'System.Description'
[string]$script:FIELD_ACCEPTANCE_CRITERIA = 'Microsoft.VSTS.Common.AcceptanceCriteria'
[string]$script:FIELD_AC_SCENARIOS = 'Custom.ACScenarios'
[string]$script:FIELD_EXTRA_INFORMATION = 'Custom.ExtraInformation'

# Bug-specific fields
[string]$script:FIELD_REPRO_STEPS = 'Microsoft.VSTS.TCM.ReproSteps'
[string]$script:FIELD_SYSTEM_INFO = 'Microsoft.VSTS.TCM.SystemInfo'
[string]$script:FIELD_FOUND_IN_BUILD = 'Microsoft.VSTS.Build.FoundInBuild'
[string]$script:FIELD_INTEGRATED_IN_BUILD = 'Microsoft.VSTS.Build.IntegratedInBuild'
[string]$script:FIELD_PRIORITY = 'Microsoft.VSTS.Common.Priority'

# Story point field (common in Scrum)
[string]$script:FIELD_STORY_POINTS = 'Microsoft.VSTS.Scheduling.StoryPoints'

# Effort field (for epics and features)
[string]$script:FIELD_EFFORT = 'Microsoft.VSTS.Scheduling.Effort'

# Task-specific time tracking fields
[string]$script:FIELD_ORIGINAL_ESTIMATE = 'Microsoft.VSTS.Scheduling.OriginalEstimate'
[string]$script:FIELD_REMAINING_WORK = 'Microsoft.VSTS.Scheduling.RemainingWork'
[string]$script:FIELD_COMPLETED_WORK = 'Microsoft.VSTS.Scheduling.CompletedWork'

# Parent/Link field
[string]$script:FIELD_PARENT = 'System.Parent'

# ============================================================================
# Query Operators
# ============================================================================

[string]$script:QUERY_OP_EQUALS = '='
[string]$script:QUERY_OP_CONTAINS = 'CONTAINS'
[string]$script:QUERY_OP_AND = 'AND'

# ============================================================================
# REST API Methods
# ============================================================================

[string]$script:HTTP_METHOD_GET = 'Get'
[string]$script:HTTP_METHOD_POST = 'Post'
[string]$script:HTTP_METHOD_PATCH = 'Patch'
[string]$script:HTTP_METHOD_DELETE = 'Delete'

# ============================================================================
# PATCH Operation Types
# ============================================================================

[string]$script:PATCH_OP_ADD = 'add'
[string]$script:PATCH_OP_REPLACE = 'replace'
[string]$script:PATCH_OP_REMOVE = 'remove'

# ============================================================================
# HTTP Headers
# ============================================================================

[string]$script:HEADER_CONTENT_TYPE_JSON = 'application/json'
[string]$script:HEADER_CONTENT_TYPE_PATCH = 'application/json-patch+json'

# ============================================================================
# Error Messages
# ============================================================================

[string]$script:ERROR_WORKITEM_ALREADY_EXISTS = 'Work item with title "{0}" already exists. Use -UpdateExisting to update it.'
[string]$script:ERROR_WORKITEM_NOT_FOUND = 'Work item not found: {0}'
[string]$script:ERROR_INVALID_WORKITEM_ID = 'Invalid work item ID: {0}'
[string]$script:ERROR_INVALID_PARENT_ID = 'Invalid parent work item ID: {0}'
[string]$script:ERROR_MISSING_REQUIRED_PARAM = 'Required parameter "{0}" is missing or empty.'
[string]$script:ERROR_INVALID_STORY_POINTS = 'Story points must be a non-negative integer. Provided: {0}'
[string]$script:ERROR_PAT_TOKEN_MISSING = 'PAT token not available. Set GMD_AZDO_MACHINE_WORKITEMSRW environment variable or use -PatToken parameter.'

# ============================================================================
# Regex Patterns
# ============================================================================

[regex]$script:REGEX_WORK_ITEM_ID = '^\d+$'
[regex]$script:REGEX_STORY_POINTS = '^\d+(\.\d+)?$'

# ============================================================================
# Markdown Parsing Patterns for Hierarchy
# ============================================================================

[regex]$script:REGEX_MARKDOWN_EPIC = '^\#\s+Epic:\s*(.+)$'           # # Epic: Title
[regex]$script:REGEX_MARKDOWN_FEATURE = '^\#\#\s+Feature:\s*(.+)$'      # ## Feature: Title
[regex]$script:REGEX_MARKDOWN_STORY = '^\#\#\#\s+Story:\s*(.+)$'      # ### Story: Title
[regex]$script:REGEX_MARKDOWN_TASK = '^\#\#\#\#\s+Task:\s*(.+)$'       # #### Task: Title
[regex]$script:REGEX_MARKDOWN_BUG = '^\#\#\#\#\s+Bug:\s*(.+)$'       # #### Bug: Title
[regex]$script:REGEX_MARKDOWN_SECTION_HEADER = '^\#\#\#\#\s+(.+)$'  # #### Section Header (AC, ACS, EI, Repro Steps, etc.)
[regex]$script:REGEX_MARKDOWN_TAGS = '^\*\*tags\*\*:\s*(.+)$'     # **tags**: tag1, tag2
[regex]$script:REGEX_MARKDOWN_DESCRIPTION_START = '^\*\*Description\*\*:\s*(.*)$'     # **Description**: optional inline content
[regex]$script:REGEX_MARKDOWN_AC = '^\s*-\s*AC:\s*(.+)$'     # - AC: Acceptance Criteria
[regex]$script:REGEX_MARKDOWN_AC_SCENARIOS = '^\s*-\s*ACS:\s*(.+)$'     # - ACS: Acceptance Criteria Scenarios
[regex]$script:REGEX_MARKDOWN_EXTRA_INFO = '^\s*-\s*EI:\s*(.+)$'     # - EI: Extra Information
[regex]$script:REGEX_MARKDOWN_SP = '^\s*-\s*SP:\s*(\d+)$'    # - SP: 5
[regex]$script:REGEX_MARKDOWN_EFFORT = '^\*\*Effort\*\*:\s*(\d+)$'    # **Effort**: 21
[regex]$script:REGEX_MARKDOWN_PRIORITY = '^\*\*Priority\*\*:\s*([1-4])$'    # **Priority**: 1-4
[regex]$script:REGEX_MARKDOWN_ORIGINAL_ESTIMATE = '^\*\*Original Estimate\*\*:\s*(\d+(?:\.\d+)?)$'    # **Original Estimate**: 8
[regex]$script:REGEX_MARKDOWN_REMAINING = '^\*\*Remaining\*\*:\s*(\d+(?:\.\d+)?)$'    # **Remaining**: 5
[regex]$script:REGEX_MARKDOWN_COMPLETED = '^\*\*Completed\*\*:\s*(\d+(?:\.\d+)?)$'    # **Completed**: 3

# Header level validation patterns  
[regex]$script:REGEX_MARKDOWN_HEADER_LEVEL_1_2 = '^\s*#{1,2}\s'     # # or ##
[regex]$script:REGEX_MARKDOWN_HEADER_LEVEL_1_2_3 = '^\s*#{1,3}\s'   # #, ##, or ###
[regex]$script:REGEX_MARKDOWN_HEADER_LEVEL_1_2_3_4 = '^\s*#{1,4}\s'   # #, ##, ###, or ####

# Title version suffix pattern for stripping work items with version suffixes like (001), (01), (7), etc.
# Used as: $normalized = $Title -replace $REGEX_TITLE_VERSION_SUFFIX, ''
[regex]$script:REGEX_TITLE_VERSION_SUFFIX = '\s*\(\d+\)\s*$'        # (NNN) where N is any digit count, at end of string

# ============================================================================
# Tag Modes
# ============================================================================

[string]$script:TAG_MODE_ADD = 'Add'
[string]$script:TAG_MODE_REPLACE = 'Replace'
[string]$script:TAG_MODE_REMOVE = 'Remove'
[string[]]$script:VALID_TAG_MODES = @('Add', 'Replace', 'Remove')
