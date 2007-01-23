<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2006, 2007 University of Utah and the Flux Group.
# All rights reserved.
#
class Project
{
    var	$project;
    var $group;

    #
    # Constructor by lookup on unique index.
    #
    function Project($pid_idx) {
	$safe_pid_idx = addslashes($pid_idx);

	$query_result =
	    DBQueryWarn("select * from projects ".
			"where pid_idx='$safe_pid_idx'");

	if (!$query_result || !mysql_num_rows($query_result)) {
	    $this->project = NULL;
	    return;
	}
	$this->project = mysql_fetch_array($query_result);
	$this->group   = null;
    }

    # Hmm, how does one cause an error in a php constructor?
    function IsValid() {
	return !is_null($this->project);
    }

    # Lookup by pid_idx.
    function Lookup($pid_idx) {
	$foo = new Project($pid_idx);

	if (! $foo->IsValid()) {
	    # Try lookup by plain uid.
	    $foo = Project::LookupByPid($pid_idx);
	    
	    if (!$foo || !$foo->IsValid())
		return null;

	    # Return here, in case I add a cache and forget to do this.
	    return $foo;
	}
	return $foo;
    }

    # Backwards compatable lookup by pid. Will eventually flush this.
    function LookupByPid($pid) {
	$safe_pid = addslashes($pid);

	$query_result =
	    DBQueryWarn("select pid_idx from projects where pid='$safe_pid'");

	if (!$query_result || !mysql_num_rows($query_result)) {
	    return null;
	}
	$row = mysql_fetch_array($query_result);
	$idx = $row['pid_idx'];

	$foo = new Project($idx); 

	if ($foo->IsValid())
	    return $foo;
	
	return null;
    }
    
    #
    # Refresh an instance by reloading from the DB.
    #
    function Refresh() {
	if (! $this->IsValid())
	    return -1;

	$pid_idx = $this->pid_idx();

	$query_result =
	    DBQueryWarn("select * from projects where pid_idx='$pid_idx'");
    
	if (!$query_result || !mysql_num_rows($query_result)) {
	    $this->project = NULL;
	    return -1;
	}
	$this->project = mysql_fetch_array($query_result);
	$this->group   = null;
	return 0;
    }

    # accessors
    function field($name) {
	return (is_null($this->project) ? -1 : $this->project[$name]);
    }
    function pid_idx()	     { return $this->field("pid_idx"); }
    function pid()	     { return $this->field("pid"); }
    function created()       { return $this->field("created"); }
    function expires()       { return $this->field("expires"); }
    function name()          { return $this->field("name"); }
    function URL()           { return $this->field("URL"); }
    function funders()       { return $this->field("funders"); }
    function addr()          { return $this->field("addr"); }
    function head_uid()      { return $this->field("head_uid"); }
    function head_idx()      { return $this->field("head_idx"); }
    function num_members()   { return $this->field("num_members"); }
    function num_pcs()       { return $this->field("num_pcs"); }
    function num_sharks()    { return $this->field("num_sharks"); }
    function num_pcplab()    { return $this->field("num_pcplab"); }
    function num_ron()       { return $this->field("num_ron"); }
    function why()           { return $this->field("why"); }
    function control_node()  { return $this->field("control_node"); }
    function approved()      { return $this->field("approved"); }
    function inactive()      { return $this->field("inactive"); }
    function date_inactive() { return $this->field("date_inactive"); }
    function public()        { return $this->field("public"); }
    function public_whynot() { return $this->field("public_whynot"); }
    function expt_count()    { return $this->field("expt_count"); }
    function expt_last()     { return $this->field("expt_last"); }
    function pcremote_ok()   { return $this->field("pcremote_ok"); }
    function default_user_interface()
	                     { return $this->field("default_user_interface"); }
    function linked_to_us()  { return $this->field("linked_to_us"); }
    function cvsrepo_public(){ return $this->field("cvsrepo_public"); }

    function unix_gid() {
	$group = $this->LoadGroup();
	
	return $group->unix_gid();
    }
    function unix_name() {
	$group = $this->LoadGroup();

	return $group->unix_name();
    }

    #
    # At some point we will stop passing pid and start using pid_idx.
    # Use this function to avoid having to change a bunch of code twice.
    #
    function URLParam() {
	return $this->pid();
    }

    #
    # Class function to create new project and return object.
    #
    function NewProject($pid, $leader, $args) {
	global $TBBASE, $TBMAIL_APPROVAL, $TBMAIL_AUDIT, $TBMAIL_WWW;
	
	#
	# The array of inserts is assumed to be safe already. Generate
	# a list of actual insert clauses to be joined below.
	#
	$insert_data = array();
	
	foreach ($args as $name => $value) {
	    $insert_data[] = "$name='$value'";
	}

	# First create the underlying default group for the project.
	if (! ($newgroup = Group::NewGroup(null, $pid, $leader,
					   'Default Group', $pid))) {
	    return null;
	}

	# Every project gets a new unique index, which comes from the group.
	$pid_idx = $newgroup->gid_idx();

	# Now tack on other stuff we need.
	$insert_data[] = "pid='$pid'";
	$insert_data[] = "pid_idx='$pid_idx'";
	$insert_data[] = "head_uid='" . $leader->uid() . "'";
	$insert_data[] = "head_idx='" . $leader->uid_idx() . "'";
	$insert_data[] = "created=now()";

	# Insert into DB. Should probably lock the table ...
	if (!DBQuerywarn("insert into projects set ".
			 implode(",", $insert_data))) {
	    $newgroup->Delete();
	    return null;
	}

	if (! DBQueryWarn("insert into project_stats (pid, pid_idx) ".
			  "values ('$pid', $pid_idx)")) {
	    $newgroup->Delete();
	    DBQueryFatal("delete from projects where pid_idx='$pid_idx'");
	    return null;
	}
	$newproject = Project::Lookup($pid_idx);
	if (! $newproject)
	    return null;

	#
	# The creator of a group is not automatically added to the group,
	# but we do want that for a new project. 
	#
	if ($newgroup->AddNewMember($leader) < 0) {
	    $newgroup->Delete();
	    DBQueryWarn("delete from project_stats where pid_idx=$pid_idx");
	    DBQueryWarn("delete from projects where pid_idx=$pid_idx");
	    return null;
	}

	return $newproject;
    }

    function NewNewProject($leader, $args, &$error) {
	global $suexec_output, $suexec_output_array;

        #
        # Generate a temporary file and write in the XML goo.
        #
	$xmlname = tempnam("/tmp", "newproj");
	if (! $xmlname) {
	    TBERROR("Could not create temporary filename", 0);
	    $error = "Transient error; please try again later.";
	    return null;
	}
	if (! ($fp = fopen($xmlname, "w"))) {
	    TBERROR("Could not open temp file $xmlname", 0);
	    $error = "Transient error; please try again later.";
	    return null;
	}

	# Need to say who is going to be leading this project.
	$args["leader"] = $leader->uid();

	fwrite($fp, "<project>\n");
	foreach ($args as $name => $value) {
	    fwrite($fp, "<attribute name=\"$name\">");
	    fwrite($fp, "  <value>" . htmlspecialchars($value) . "</value>");
	    fwrite($fp, "</attribute>\n");
	}
	fwrite($fp, "</project>\n");
	fclose($fp);
	chmod($xmlname, 0666);

	$retval = SUEXEC("nobody", "nobody", "webnewproj $xmlname",
			 SUEXEC_ACTION_IGNORE);

	if ($retval) {
	    if ($retval < 0) {
		$error = "Transient error; please try again later.";
		SUEXECERROR(SUEXEC_ACTION_CONTINUE);
	    }
	    else {
		$error = $suexec_output;
	    }
	    return null;
	}

        #
        # Parse the last line of output. Ick.
        #
	unset($matches);
	
	if (!preg_match("/^User\s+(\w+)\/(\d+)\s+/",
			$suexec_output_array[count($suexec_output_array)-1],
			$matches)) {
	    $error = "Transient error; please try again later.";
	    SUEXECERROR(SUEXEC_ACTION_CONTINUE);
	    return null;
	}
	$pid_idx = $matches[2];
	$newproj = Project::Lookup($pid_idx);
	if (! $newproj) {
	    $error = "Transient error; please try again later.";
	    TBERROR("Could not lookup new project $pid_idx", 0);
	    return null;
	}
	# Unlink this here, so that the file is left behind in case of error.
	# We can then create the project by hand from the xmlfile, if desired.
	unlink($xmlname);
	return $newproj;
    }    

    #
    # Access Check, which for now uses the global function to avoid duplication
    # until all code is changed.
    #
    function AccessCheck($user, $access_type) {
	return TBProjAccessCheck($user->uid(),
				 $this->pid(), $this->pid(),
				 $access_type);
    }

    #
    # Load the default group for a project lazily.
    #
    function LoadGroup() {
	# Note: pid_idx=gid_idx for the default group
	$gid_idx = $this->pid_idx();

	if (! ($group = Group::Lookup($gid_idx))) {
	    TBERROR("Project::LoadGroup: Could not load group $gid_idx!", 1);
	}
	$this->group = $group;
	return $group;
    }
    function Group() {
	return $this->LoadGroup();
    }

    #
    # Return user object for leader.
    #
    function GetLeader() {
	$head_idx = $this->head_idx();

	if (! ($leader = User::Lookup($head_idx))) {
	    TBERROR("Could not find user object for $head_idx", 1);
	}
	return $leader;
    }

    #
    # Add *new* member to project group; starts out with trust=none.
    #
    function AddNewMember($user) {
	$group = $this->LoadGroup();

	return $group->AddNewMember($user);
    }

    #
    # Check if user is a member of this project (well, group)
    #
    function IsMember($user, &$approved) {
	$group = $this->LoadGroup();

	return $group->IsMember($user, $approved);
    }

    #
    # Member list for a group.
    #
    function MemberList() {
	$pid_idx = $this->pid_idx();
	$result  = array();

	$query_result =
	    DBQueryFatal("select uid_idx from group_membership ".
			 "where pid_idx='$pid_idx' and gid_idx=pid_idx");

	while ($row = mysql_fetch_array($query_result)) {
	    $uid_idx = $row["uid_idx"];

	    if (! ($user =& User::Lookup($uid_idx))) {
		TBERROR("Project::MemberList: ".
			"Could not load user $uid_idx!", 1);
	    }
	    $result[] =& $user;
	}
	return $result;
    }

    #
    # List of subgroups for a project member (not including default group).
    #
    function GroupList($user) {
	$pid_idx = $this->pid_idx();
	$uid_idx = $user->uid_idx();
	$result  = array();

	$query_result =
	    DBQueryFatal("select gid_idx from group_membership ".
			 "where pid_idx='$pid_idx' and pid_idx!=gid_idx and ".
			 "      uid_idx='$uid_idx'");

	while ($row = mysql_fetch_array($query_result)) {
	    $gid_idx = $row["gid_idx"];

	    if (! ($group = Group::Lookup($gid_idx))) {
		TBERROR("Project::GroupList: ".
			"Could not load group $gid_idx!", 1);
	    }
	    $result[] = $group;
	}
	return $result;
    }

    #
    # Change the leader for a project. Done *only* before project is
    # approved.
    #
    function ChangeLeader($leader) {
	$group   = $this->LoadGroup();
	$idx     = $this->pid_idx();
	$uid     = $leader->uid();
	$uid_idx = $leader->uid_idx();

	DBQueryFatal("update projects set ".
		     "  head_uid='$uid',head_idx='$uid_idx' ".
		     "where pid_idx='$idx'");

	$this->project["head_uid"] = $uid;
	$this->project["head_idx"] = $uid_idx;
	return $group->ChangeLeader($leader);
    }
    
    #
    # Change various fields.
    #
    function SetApproved($approved) {
	$idx   = $this->pid_idx();

	if ($approved)
	    $approved = 1;
	else
	    $approved = 0;
	
	DBQueryFatal("update projects set approved='$approved' ".
		     "where pid_idx='$idx'");

	$this->project["approved"] = $approved;
	return 0;
    }
    function SetRemoteOK($ok) {
	$idx    = $this->pid_idx();
	$safeok = addslashes($ok);

	DBQueryFatal("update projects set pcremote_ok='$safeok' ".
		     "where pid_idx='$idx'");

	$this->project["pcremote_ok"] = $ok;
	return 0;
    }

    function Show() {
	global $WIKISUPPORT, $CVSSUPPORT, $TBPROJ_DIR, $TBCVSREPO_DIR;
	global $MAILMANSUPPORT, $OPSCVSURL, $USERNODE;

	$group = $this->Group();

	$pid                    = $this->pid();
	$proj_idx		= $this->pid_idx();
	$proj_created		= $this->created();
	$proj_name		= $this->name();
	$proj_URL		= $this->URL();
	$proj_public		= YesNo($this->public());
	$proj_funders		= $this->funders();
	$proj_head_idx		= $this->head_idx();
	$proj_members		= $this->num_members();
	$proj_pcs		= $this->num_pcs();
        # These are now booleans, not actual counts.
	$proj_ronpcs		= YesNo($this->num_ron());
	$proj_plabpcs		= YesNo($this->num_pcplab());
	$proj_linked		= YesNo($this->linked_to_us());
	$proj_why		= nl2br($this->why());
	$approved		= YesNo($this->approved());
	$expt_count		= $this->expt_count();
	$expt_last		= $this->expt_last();
	$wikiname		= $group->wikiname();
	$cvsrepo_public		= $this->cvsrepo_public();

	if (! ($head_user = User::Lookup($proj_head_idx))) {
	    TBERROR("Could not lookup object for user $proj_head_idx", 1);
	}
	$showuser_url  = CreateURL("showuser", $head_user);
	$showproj_url  = CreateURL("showproject", $this);
	$proj_head_uid = $head_user->uid();

	if (!$expt_last) {
	    $expt_last = "&nbsp;";
	}

	echo "<center>
              <h3>Project Profile</h3>
              </center>
              <table align=center cellpadding=2 border=1>\n";
    
        #
        # Generate the table.
        # 
	echo "<tr>
                  <td>Name: </td>
                  <td class=\"left\">
                      <a href='showproj_url'>$pid ($proj_idx)</a></td>
              </tr>\n";
    
	echo "<tr>
                  <td>Description: </td>
                  <td class=\"left\">$proj_name</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Project Head: </td>
                  <td class=\"left\">
                      <a href='$showuser_url'>$proj_head_uid</a></td>
              </tr>\n";
    
	echo "<tr>
              <td>URL: </td>
                  <td class=\"left\">
                      <a href='$proj_URL'>$proj_URL</a></td>
              </tr>\n";

	if ($WIKISUPPORT && isset($wikiname)) {
	    $wikiurl = "gotowiki.php3?redurl=$wikiname/WebHome";
	
	    echo "<tr>
                      <td>Project Wiki:</td>
                      <td class=\"left\">
                          <a href='$wikiurl'>$wikiname</a></td>
                  </tr>\n";
	}
	if ($CVSSUPPORT) {
	    $cvsdir = "$TBCVSREPO_DIR/$pid";
	    $cvsurl = "cvsweb/cvsweb.php3?pid=$pid";
	
	    echo "<tr>
                      <td>Project CVS Repository:</td>
                      <td class=\"left\">
                          $cvsdir <a href='$cvsurl'>(CVSweb)</a></td>
                  </tr>\n";

	    $YesNo = YesNo($cvsrepo_public);
	    $flip  = ($cvsrepo_public ? 0 : 1);
	    echo "<tr>
                      <td>CVS Repository Publically Readable?:</td>
                      <td><a href=toggle.php?pid=$pid&type=cvsrepo_public".
		          "&value=$flip>$YesNo</a> (Click to toggle)</td>
                  </tr>\n";

	    if ($cvsrepo_public) {
		$puburl  = "$OPSCVSURL/?cvsroot=$pid";
		$pserver = ":pserver:anoncvs@$USERNODE:/cvsrepos/$pid";
		
		echo "<tr>
                          <td>Public CVSWeb Address:</td>
                          <td><a href=$puburl>" .
		                 htmlspecialchars($puburl) . "</a></td>
                      </tr>\n";

		echo "<tr>
                          <td>CVS pserver Address:</td>
                          <td>" . htmlspecialchars($pserver) . "</td>
                      </tr>\n";
	    }
	}

	if ($MAILMANSUPPORT) {
	    $mmurl   = "gotommlist.php3?pid=$pid";

	    echo "<tr>
                      <td>Project Mailing List:</td>
                      <td class=\"left\">
                          <a href='$mmurl'>${pid}-users</a> ";
	    if (ISADMIN()) {
		$mmurl .= "&wantadmin=1";
		echo "<a href='$mmurl'>(admin access)</a>";
	    }
	    echo "    </td>
                  </tr>\n";
	}

	echo "<tr>
                  <td>Publicly Visible: </td>
                  <td class=\"left\">$proj_public</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Link to Us?: </td>
                  <td class=\"left\">$proj_linked</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Funders: </td>
                  <td class=\"left\">$proj_funders</td>
              </tr>\n";

	echo "<tr>
                  <td>#Project Members: </td>
                  <td class=\"left\">$proj_members</td>
              </tr>\n";
    
	echo "<tr>
                  <td>#PCs: </td>
                  <td class=\"left\">$proj_pcs</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Planetlab Access: </td>
                  <td class=\"left\">$proj_plabpcs</td>
              </tr>\n";
    
	echo "<tr>
                  <td>RON Access: </td>
                  <td class=\"left\">$proj_ronpcs</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Created: </td>
                  <td class=\"left\">$proj_created</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Experiments Created:</td>
                  <td class=\"left\">$expt_count</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Date of last experiment:</td>
                  <td class=\"left\">$expt_last</td>
              </tr>\n";
    
	echo "<tr>
                  <td>Approved?: </td>
                  <td class=\"left\">$approved</td>
	      </tr>\n";

	echo "<tr>
                  <td colspan='2'>Why?:</td>
              </tr>\n";
    
	echo "<tr>
                  <td colspan='2' width=600>$proj_why</td>
              </tr>\n";
    
	echo "</table>\n";
    }

    function ShowGroupList() {
	$pid_idx  = $this->pid_idx();

	$query_result =
	    DBQueryFatal("select * from groups where pid_idx='$pid_idx'");

	if (!$query_result || !mysql_num_rows($query_result)) {
	    return;
	}

	echo "<h3>Project Groups</h3>\n";
	echo "<table align=center border=1>\n";
	echo "<tr>
               <th>GID</th>
               <th>Description</th>
               <th>Leader</th>
              </tr>\n";

	while ($row = mysql_fetch_array($query_result)) {
	    $gid      = $row[gid];
	    $desc     = $row[description];
	    $leader   = $row[leader];

	    if (! ($leader_user = User::Lookup($leader))) {
		TBERROR("Could not lookup object for user $leader", 1);
	    }
	    $showuser_url = CreateURL("showuser", $leader_user);

	    echo "<tr>
                   <td><A href='showgroup.php3?pid=$pid&gid=$gid'>$gid</a></td>
                   <td>$desc</td>
                   <td><A href='$showuser_url'>$leader</A></td>
                 </tr>\n";
	}
	echo "</table>\n";
    }

    function ShowStats() {
	$pid_idx  = $this->pid_idx();

	$query_result =
	    DBQueryFatal("select * from project_stats ".
			 "where pid_idx='$pid_idx'");

	if (! mysql_num_rows($query_result)) {
	    return;
	}
	$row = mysql_fetch_assoc($query_result);

        #
        # Not pretty printed yet.
        #
	echo "<table align=center border=1>\n";
    
	foreach($row as $key => $value) {
	    echo "<tr>
                      <td>$key:</td>
                      <td>$value</td>
                  </tr>\n";
	}
	echo "</table>\n";
    }
}
