#!/usr/bin/env node
/**
 * Digest Schema Validator
 * Validates digest JSON files against expected schema
 *
 * Usage: node validate-digest.js path/to/digest.json
 */

const fs = require('fs');
const path = require('path');

const REQUIRED_FIELDS = {
  root: ['date', 'generated_at', 'channels', 'jira_mentions', 'executive_summary', 'summary_stats'],
  channel: ['channel', 'channel_id', 'threads'],
  thread: ['thread_ts', 'thread_link', 'participants', 'summary', 'actions_needed'],
  action: ['action', 'owner', 'urgency'],
  executive_summary: ['my_actions', 'others_actions', 'key_highlights'],
  summary_stats: ['total_channels', 'total_threads', 'total_actions']
};

const VALID_URGENCIES = ['today', 'this_week', 'later'];

function validateDigest(digestPath) {
  const errors = [];

  // Read file
  let digest;
  try {
    const content = fs.readFileSync(digestPath, 'utf8');
    digest = JSON.parse(content);
  } catch (err) {
    return [`Failed to read/parse ${digestPath}: ${err.message}`];
  }

  // Check root fields
  REQUIRED_FIELDS.root.forEach(field => {
    if (!(field in digest)) {
      errors.push(`Missing root field: ${field}`);
    }
  });

  // Validate date format
  if (digest.date && !/^\d{4}-\d{2}-\d{2}$/.test(digest.date)) {
    errors.push(`Invalid date format: ${digest.date} (expected YYYY-MM-DD)`);
  }

  // Validate channels
  if (Array.isArray(digest.channels)) {
    digest.channels.forEach((channel, idx) => {
      REQUIRED_FIELDS.channel.forEach(field => {
        if (!(field in channel)) {
          errors.push(`Channel ${idx} missing field: ${field}`);
        }
      });

      // Validate channel_id format (should start with C or D)
      if (channel.channel_id && !/^[CD][A-Z0-9]+$/.test(channel.channel_id)) {
        errors.push(`Channel ${idx} has invalid channel_id: ${channel.channel_id}`);
      }

      // Validate threads
      if (Array.isArray(channel.threads)) {
        channel.threads.forEach((thread, tidx) => {
          REQUIRED_FIELDS.thread.forEach(field => {
            if (!(field in thread)) {
              errors.push(`Channel ${idx}, Thread ${tidx} missing field: ${field}`);
            }
          });

          // Validate thread_link contains channel_id
          if (thread.thread_link && channel.channel_id) {
            if (!thread.thread_link.includes(channel.channel_id)) {
              errors.push(`Channel ${idx}, Thread ${tidx} thread_link doesn't contain channel_id ${channel.channel_id}`);
            }
          }

          // Validate actions
          if (Array.isArray(thread.actions_needed)) {
            thread.actions_needed.forEach((action, aidx) => {
              REQUIRED_FIELDS.action.forEach(field => {
                if (!(field in action)) {
                  errors.push(`Channel ${idx}, Thread ${tidx}, Action ${aidx} missing field: ${field}`);
                }
              });

              if (action.urgency && !VALID_URGENCIES.includes(action.urgency)) {
                errors.push(`Invalid urgency "${action.urgency}" (must be: ${VALID_URGENCIES.join(', ')})`);
              }
            });
          }
        });
      }
    });
  }

  // Validate executive_summary
  if (digest.executive_summary) {
    REQUIRED_FIELDS.executive_summary.forEach(field => {
      if (!(field in digest.executive_summary)) {
        errors.push(`executive_summary missing field: ${field}`);
      }
    });
  }

  // Validate summary_stats
  if (digest.summary_stats) {
    REQUIRED_FIELDS.summary_stats.forEach(field => {
      if (!(field in digest.summary_stats)) {
        errors.push(`summary_stats missing field: ${field}`);
      }
    });
  }

  return errors;
}

// Run validation
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node validate-digest.js <digest.json>');
    process.exit(1);
  }

  const digestPath = args[0];
  const errors = validateDigest(digestPath);

  if (errors.length > 0) {
    console.error(`❌ Validation failed for ${digestPath}:`);
    errors.forEach(err => console.error(`  - ${err}`));
    process.exit(1);
  } else {
    console.log(`✅ ${digestPath} is valid`);
    process.exit(0);
  }
}

module.exports = { validateDigest };
