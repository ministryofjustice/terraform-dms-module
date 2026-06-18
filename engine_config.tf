locals {
  source_engine_configs = {
    oracle = {
      stream_position_column                = "SCN"
      password                              = "${local.database_credentials["oracle_password"]},${local.database_credentials["asm_password"]}"
      default_source_extra_connection_attrs = null
      supports_source_rds_slot_alarms       = false
    }
    postgres = {
      stream_position_column                = "STREAM_POSITION"
      password                              = local.database_credentials["password"]
      default_source_extra_connection_attrs = "PluginName=test_decoding;CaptureDDLs=N;HeartbeatEnable=true;HeartbeatFrequency=5;HeartbeatSchema=public;"
      supports_source_rds_slot_alarms       = true
    }
  }

  source_engine_config = local.source_engine_configs[var.dms_source.engine_name]

  source_extra_connection_attributes = (
    var.dms_source.extra_connection_attributes != null
    ? var.dms_source.extra_connection_attributes
    : local.source_engine_config.default_source_extra_connection_attrs
  )
}
