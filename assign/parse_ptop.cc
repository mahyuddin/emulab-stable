/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2000-2003 University of Utah and the Flux Group.
 * All rights reserved.
 */

#include "port.h"

#include <boost/graph/adjacency_list.hpp>

#include <iostream.h>

using namespace boost;

#include "delay.h"
#include "physical.h"
#include "parser.h"

extern name_pvertex_map pname2vertex;
extern name_count_map ptypes;

#define ptop_error(s) errors++;cout << "PTOP:" << line << ": " << s << endl; exit(EXIT_FATAL)
#define ptop_error_noline(s) errors++;cout << "PTOP: " << s << endl

// Used to do late binding of subnode names to pnodes, so that we're no
// dependant on their ordering in the ptop file, which can be annoying to get
// right.
// Returns the number of errors found
int bind_ptop_subnodes() {
    int errors = 0;

    // Iterate through all pnodes looking for ones that are subnodes
    pvertex_iterator vit,vendit;
    tie(vit,vendit) = vertices(PG);
    for (;vit != vendit;++vit) {
	tb_pnode *pnode = get(pvertex_pmap,*vit);
	if (!pnode->subnode_of_name.empty()) {
	    if (pname2vertex.find(pnode->subnode_of_name) ==
		    pname2vertex.end()) {
		ptop_error_noline(pnode->name << " is a subnode of a " <<
			"non-existent node, " << pnode->subnode_of_name << ".");
			continue;
		}
		pvertex parent_pv = pname2vertex[pnode->subnode_of_name];
		pnode->subnode_of = get(pvertex_pmap,parent_pv);
		pnode->subnode_of->has_subnode = true;
	}
    }

    return errors;
}

int parse_ptop(tb_pgraph &PG, tb_sgraph &SG, istream& i)
{
  int num_nodes = 0;
  int line=0,errors=0;
  char inbuf[16384];
  string_vector parsed_line;

  while (!i.eof()) {
    line++;
    i.getline(inbuf,16384);
    parsed_line = split_line(inbuf,' ');
    if (parsed_line.size() == 0) {continue;}

    crope command = parsed_line[0];

    if (command.compare("node") == 0) {
      if (parsed_line.size() < 3) {
	ptop_error("Bad node line, too few arguments.");
      } else {
	num_nodes++;
	crope name = parsed_line[1];
	bool isswitch = false;
	pvertex pv = add_vertex(PG);
	tb_pnode *p = new tb_pnode(name);
	put(pvertex_pmap,pv,p);
	
	unsigned int i;
	for (i = 2;
	     (i < parsed_line.size()) &&
	       (parsed_line[i].compare("-") != 0);++i) {
	  crope type,load;
	  if (split_two(parsed_line[i],':',type,load,"1") != 0) {
	    ptop_error("Bad node line, no load for type: " << type << ".");
	  }
	  // Check to see if this is a static type
	  bool is_static = false;
	  if (type[0] == '*') {
	    is_static = true;
	    type.pop_front();
	  }
	  int iload;
	  if (!load.compare("*")) { // Allow * to mean unlimited
	                            // (okay, a really big number)
	    iload = 10000000;
	  } else if (sscanf(load.c_str(),"%d",&iload) != 1) {
	    ptop_error("Bad node line, bad load: " << load << ".");
	    iload = 1;
	  }
	  if (ptypes.find(type) == ptypes.end()) {
	      ptypes[type] = iload;
	  } else {
	      ptypes[type] += iload;
	  }
	  if (type.compare("switch") == 0) {
	    isswitch = true;
	    p->is_switch = true;
	    p->types["switch"] = new tb_pnode::type_record(1,false);
	    svertex sv = add_vertex(SG);
	    tb_switch *s = new tb_switch();
	    put(svertex_pmap,sv,s);
	    s->mate = pv;
	    p->sgraph_switch = sv;
	    p->switches.insert(pv);
	  } else {
	    p->types[type] = new tb_pnode::type_record(iload,is_static);
	  }
	}
	for (i=i+1;(i<parsed_line.size()) && (parsed_line[i].compare("-")) ;++i) {
	  crope feature,cost;
	  if (split_two(parsed_line[i],':',feature,cost,"0") != 0) {
	    ptop_error("Bad node line, no cost for feature: " <<
		       feature << ".");
	  }
	  double gcost;
	  if (sscanf(cost.c_str(),"%lg",&gcost) != 1) {
	    ptop_error("Bad node line, bad cost: " << gcost << ".");
	    gcost = 0;
	  }

	  p->features.push_front(tb_node_featuredesire(feature,gcost));

	}
	/*
	 * Parse any other node options or flags
	 */
	for (i=i+1; i < parsed_line.size(); ++i) {
	    crope flag,value;
	    split_two(parsed_line[i],':',flag,value,"(null)");
	    if (flag.compare("trivial_bw") == 0) {
		// Handle trivial bandwidth spec
		int trivial_bw;
		if (sscanf(value.c_str(),"%i",&trivial_bw) != 1) {
		    ptop_error("Bad bandwidth given for trivial_bw: " << value
			    << endl);
		    trivial_bw = 0;
		}
		p->trivial_bw = trivial_bw;
	    } else if (flag.compare("subnode_of") == 0) {
		// Handle subnode relationships
		if (!p->subnode_of_name.empty()) {
		    ptop_error("Can't be a subnode of two nodes");
		    continue;
		} else {
		    // Just store the name for now, we'll do late binding to
		    // an actual pnode later
		    p->subnode_of_name = value;
		}
	    } else if (flag.compare("unique") == 0) {
		// Means that we should never put this pnode into a ptype with
		// other pnodes
		p->unique = true;
	    } else {
		ptop_error("Bad flag given: " << flag << ".");
	    }
	}
	p->features.sort();
	pname2vertex[name] = pv;
      }
    } else if (command.compare("link") == 0) {
      if (parsed_line.size() < 8) {
	ptop_error("Bad link line, too few arguments.");
      }
      int num = 1;
#ifdef PENALIZE_BANDWIDTH
      float penalty;
      if (parsed_line.size() == 9) {
	if (sscanf(parsed_line[8].c_str(),"%f",&penalty) != 1) {
	  ptop_error("Bad number argument: " << parsed_line[8] << ".");
	  penalty=1.0;
	}
      }
#endif

#if 0
#ifdef FIX_PLINK_ENDPOINTS
      bool fixends;
#ifdef FIX_PLINKS_DEFAULT
      fixends = true;
#else
      fixends = false;
#endif
      if (parsed_line.size() == 10) {
	  if (parsed_line[9].compare("fixends") == 0) {
	      fixends = true;
	  }
      }
#else
      if (parsed_line.size() > 9) {
	ptop_error("Bad link line, too many arguments.");
      }
#endif
#endif

      crope name = parsed_line[1];
      crope src,srcmac;
      split_two(parsed_line[2],':',src,srcmac,"(null)");
      crope dst,dstmac;
      split_two(parsed_line[3],':',dst,dstmac,"(null)");
      crope bw = parsed_line[4];
      crope delay = parsed_line[5];
      crope loss = parsed_line[6];
      crope link_type = parsed_line[7];
      int ibw,idelay;
      double gloss;

      
      if ((sscanf(bw.c_str(),"%d",&ibw) != 1) ||
	  (sscanf(delay.c_str(),"%d",&idelay) != 1) ||
	  (sscanf(loss.c_str(),"%lg",&gloss) != 1)) {
	ptop_error("Bad link line, bad delay characteristics.");
      }

#define ISSWITCH(n) (n->types.find("switch") != n->types.end())
      // Check to make sure the nodes in the link actually exist
      if (pname2vertex.find(src) == pname2vertex.end()) {
	  ptop_error("Bad link line, non-existent node.");
	  continue;
      }
      if (pname2vertex.find(dst) == pname2vertex.end()) {
	  ptop_error("Bad link line, non-existent node.");
	  continue;
      }

      pvertex srcv = pname2vertex[src];
      pvertex dstv = pname2vertex[dst];
      tb_pnode *srcnode = get(pvertex_pmap,srcv);
      tb_pnode *dstnode = get(pvertex_pmap,dstv);
      
      for (int cur = 0;cur<num;++cur) {
	pedge pe = (add_edge(srcv,dstv,PG)).first;
	tb_plink *pl = new
	    tb_plink(name,tb_plink::PLINK_NORMAL,link_type,srcmac,dstmac);
	put(pedge_pmap,pe,pl);
	pl->delay_info.bandwidth = ibw;
	pl->delay_info.delay = idelay;
	pl->delay_info.loss = gloss;
#if 0
#ifdef FIX_PLINK_ENDPOINTS
	pl->fixends = fixends;
#endif
#endif
#ifdef PENALIZE_BANDWIDTH
	pl->penalty = penalty;
#endif
	if (ISSWITCH(srcnode) && ISSWITCH(dstnode)) {
	  if (cur != 0) {
	    cout <<
	      "Warning: Extra links between switches will be ignored. (" <<
	      name << ")" << endl;
	  } else {
	    svertex src_switch = get(pvertex_pmap,srcv)->sgraph_switch;
	    svertex dst_switch = get(pvertex_pmap,dstv)->sgraph_switch;
	    sedge swedge = add_edge(src_switch,dst_switch,SG).first;
	    tb_slink *sl = new tb_slink();
	    put(sedge_pmap,swedge,sl);
	    sl->mate = pe;
	    pl->is_type = tb_plink::PLINK_INTERSWITCH;
	  }
	}
	srcnode->total_interfaces++;
	dstnode->total_interfaces++;
	srcnode->link_counts[link_type]++;
	dstnode->link_counts[link_type]++;
	for (int i = 8; i < parsed_line.size(); i++) {
	  crope link_type = parsed_line[i];
	  pl->types.insert(link_type);
	  srcnode->link_counts[link_type]++;
	  dstnode->link_counts[link_type]++;
	}
	if (ISSWITCH(srcnode) &&
	    ! ISSWITCH(dstnode)) {
	  dstnode->switches.insert(srcv);
#ifdef PER_VNODE_TT
	  dstnode->total_bandwidth += ibw;
#endif
	}
	else if (ISSWITCH(dstnode) &&
		 ! ISSWITCH(srcnode)) {
	  srcnode->switches.insert(dstv);
#ifdef PER_VNODE_TT
	  srcnode->total_bandwidth += ibw;
#endif
	}
      }
    } else {
      ptop_error("Unknown directive: " << command << ".");
    }
  }

  errors += bind_ptop_subnodes();

  if (errors > 0) {exit(EXIT_FATAL);}
  
  return num_nodes;
}

